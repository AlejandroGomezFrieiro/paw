//! The window's loop: winit's events, egui's passes and OpenGL (glutin,
//! egui_glow), in place of eframe's, so that the main window is drawn
//! again only where its picture changed (crate::damage), onto what the
//! last frame left in the buffer, and shown only then
//! (`EGL_KHR_swap_buffers_with_damage`): a frame that changes nothing is
//! neither drawn nor shown. On a graphics card that saves the compositor's
//! work; on the processor (llvmpipe), where each pixel drawn costs, it is
//! most of the window's cost.
//!
//! The views in windows of their own are egui's immediate viewports, drawn
//! whole within the main window's pass, as eframe draws them.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::num::NonZeroU32;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context as _, Result, anyhow};
use egui::{ViewportBuilder, ViewportClass, ViewportCommand, ViewportId, ViewportIdPair, ViewportInfo};
use egui_glow::glow::{self, HasContext as _};
use glutin::config::{Config, ConfigTemplateBuilder};
use glutin::context::{ContextApi, ContextAttributesBuilder, GlProfile, NotCurrentContext, NotCurrentGlContext as _, PossiblyCurrentContext, PossiblyCurrentGlContext as _};
use glutin::display::{GetGlDisplay as _, GlDisplay as _};
use glutin::surface::{GlSurface as _, Surface, SurfaceAttributesBuilder, SwapInterval, WindowSurface};
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop, EventLoopProxy};
use winit::raw_window_handle::{HasDisplayHandle as _, HasWindowHandle as _, RawDisplayHandle};
use winit::window::{Window, WindowId};

use crate::damage::{Damage, Px};

/// What the loop runs: the program's window.
pub trait App {
    /// The colour the window is cleared to under everything.
    fn clear_color(&self) -> [f32; 4];
    /// The input of a frame of the main window, before egui sees it.
    fn raw_input_hook(&mut self, _ctx: &egui::Context, _raw: &mut egui::RawInput) {}
    /// Draw the main window.
    fn ui(&mut self, ui: &mut egui::Ui);
    /// Whether the main window is drawn again only where it changed
    /// (`paw.opt.window_cache`); else whole, every frame.
    fn partial(&self) -> bool {
        true
    }
    /// The window is closing.
    fn on_exit(&mut self) {}
    /// The live parts of the last pass painted again, each by its number,
    /// when nothing but the live values changed since it (crate::live):
    /// the frame is then made from the last pass's shapes and these, with
    /// no pass. None: a pass runs.
    fn replay(&mut self, _ctx: &egui::Context, _raw: &egui::RawInput) -> Option<Vec<(u32, Vec<egui::epaint::ClippedShape>)>> {
        None
    }
}

/// The OpenGL the window draws with, for the program to report.
pub struct GlInfo {
    pub renderer: String,
    pub version: String,
    /// Ask for a frame of the main window at once, from any thread. egui's
    /// own request does not reach the loop again while no pass has run
    /// since the last (a frame made from the live values runs none).
    pub wake: Arc<dyn Fn() + Send + Sync>,
}

/// A frame of a window is asked for, at a time.
#[derive(Debug)]
struct Wake {
    viewport: ViewportId,
    when: Instant,
    pass: u64,
    /// Asked by the program (`GlInfo::wake`), not by egui: never old.
    direct: bool,
}

/// How long to wait for the compositor's call to draw (Wayland paces the
/// frames so) before running the window's pass without drawing.
const MISSED_REDRAW: Duration = Duration::from_millis(250);

/// A window: the main one, or a view in a window of its own.
struct Viewport {
    ids: ViewportIdPair,
    builder: ViewportBuilder,
    info: ViewportInfo,
    /// Commands given before the window existed.
    deferred: Vec<ViewportCommand>,
    actions: Vec<egui_winit::ActionRequested>,
    window: Option<Arc<Window>>,
    state: Option<egui_winit::State>,
    surface: Option<Surface<WindowSurface>>,
}

impl Viewport {
    fn new(ids: ViewportIdPair, builder: ViewportBuilder) -> Viewport {
        Viewport { ids, builder, info: ViewportInfo::default(), deferred: Vec::new(), actions: Vec::new(), window: None, state: None, surface: None }
    }

    fn commands(&mut self, ctx: &egui::Context, mut commands: Vec<ViewportCommand>) {
        self.deferred.append(&mut commands);
        if let Some(window) = &self.window {
            egui_winit::process_viewport_commands(ctx, &mut self.info, std::mem::take(&mut self.deferred), window, &mut self.actions);
        }
    }
}

/// OpenGL, and the windows it draws.
struct Gl {
    ctx: egui::Context,
    config: Config,
    swap_interval: SwapInterval,
    current: Option<PossiblyCurrentContext>,
    not_current: Option<NotCurrentContext>,
    /// The window the context was last made current on.
    current_on: Option<ViewportId>,
    painter: egui_glow::Painter,
    viewports: HashMap<ViewportId, Viewport>,
    by_window: HashMap<WindowId, ViewportId>,
    started: Instant,
    /// GLX on the processor: the changed parts copied to the window, with
    /// no swap, so that the buffer drawn into is always the last frame.
    copy_sub: Option<CopySub>,
}

/// `glXCopySubBufferMESA`, and the display and window it copies to.
struct CopySub {
    copy: unsafe extern "C" fn(*const std::ffi::c_void, u64, i32, i32, i32, i32),
    display: *const std::ffi::c_void,
    drawable: u64,
}

/// `glXCopySubBufferMESA` for a GLX surface whose display has it.
fn copy_sub_buffer(config: &Config, surface: &Surface<WindowSurface>) -> Option<CopySub> {
    use glutin::display::{AsRawDisplay as _, RawDisplay};
    use glutin::surface::{AsRawSurface as _, RawSurface};
    let display = config.display();
    let (RawDisplay::Glx(raw), RawSurface::Glx(drawable)) = (display.raw_display(), surface.raw_surface()) else { return None };
    let query = display.get_proc_address(c"glXQueryExtensionsString");
    let copy = display.get_proc_address(c"glXCopySubBufferMESA");
    if query.is_null() || copy.is_null() {
        return None;
    }
    unsafe {
        let query: unsafe extern "C" fn(*const std::ffi::c_void, i32) -> *const std::ffi::c_char = std::mem::transmute(query);
        let names = query(raw, 0);
        if names.is_null() || !std::ffi::CStr::from_ptr(names).to_string_lossy().split(' ').any(|n| n == "GLX_MESA_copy_sub_buffer") {
            return None;
        }
        Some(CopySub { copy: std::mem::transmute::<*const std::ffi::c_void, unsafe extern "C" fn(*const std::ffi::c_void, u64, i32, i32, i32, i32)>(copy), display: raw, drawable })
    }
}

impl Gl {
    /// Make the context current on the window's surface.
    fn current(&mut self, id: ViewportId) -> Result<()> {
        let Some(surface) = self.viewports.get(&id).and_then(|v| v.surface.as_ref()) else { return Err(anyhow!("no surface")) };
        if self.current_on == Some(id)
            && let Some(current) = &self.current
            && surface.is_current(current)
        {
            return Ok(());
        }
        let not_current = match self.not_current.take() {
            Some(context) => context,
            None => {
                self.current_on = None;
                self.current.take().context("no OpenGL context")?.make_not_current()?
            }
        };
        self.current = Some(not_current.make_current(surface)?);
        self.current_on = Some(id);
        Ok(())
    }

    /// The window of a viewport, its egui state and its surface, made if
    /// missing.
    fn open(&mut self, id: ViewportId, event_loop: &ActiveEventLoop) -> Result<()> {
        let max_side = self.painter.max_texture_side();
        let viewport = self.viewports.get_mut(&id).context("no such viewport")?;
        if viewport.window.is_none() {
            let attributes = egui_winit::create_winit_window_attributes(&self.ctx, viewport.builder.clone());
            let window = glutin_winit::finalize_window(event_loop, attributes, &self.config)?;
            egui_winit::apply_viewport_builder_to_window(&self.ctx, &window, &viewport.builder);
            egui_winit::update_viewport_info(&mut viewport.info, &self.ctx, &window, true);
            viewport.window = Some(Arc::new(window));
        }
        let window = viewport.window.clone().unwrap();
        if viewport.state.is_none() {
            viewport.state = Some(egui_winit::State::new(self.ctx.clone(), id, event_loop, Some(window.scale_factor() as f32), event_loop.system_theme(), Some(max_side)));
        }
        if viewport.surface.is_none() {
            let (w, h): (u32, u32) = window.inner_size().into();
            let attributes = SurfaceAttributesBuilder::<WindowSurface>::new().build(
                window.window_handle()?.as_raw(),
                NonZeroU32::new(w).unwrap_or(NonZeroU32::MIN),
                NonZeroU32::new(h).unwrap_or(NonZeroU32::MIN),
            );
            let surface = unsafe { self.config.display().create_window_surface(&self.config, &attributes)? };
            viewport.surface = Some(surface);
            self.current(id)?;
            let viewport = &self.viewports[&id];
            if let (Some(surface), Some(current)) = (&viewport.surface, &self.current)
                && let Err(err) = surface.set_swap_interval(current, self.swap_interval)
            {
                eprintln!("paw-gui: the swap interval: {err}");
            }
        }
        if let Some(window) = &self.viewports[&id].window {
            self.by_window.insert(window.id(), id);
        }
        let viewport = self.viewports.get_mut(&id).unwrap();
        let deferred = std::mem::take(&mut viewport.deferred);
        viewport.commands(&self.ctx, deferred);
        Ok(())
    }

    /// The window has a new size: its surface too.
    fn resize(&mut self, id: ViewportId) {
        if self.current(id).is_err() {
            return;
        }
        let Some(viewport) = self.viewports.get(&id) else { return };
        if let (Some(window), Some(surface), Some(current)) = (&viewport.window, &viewport.surface, &self.current) {
            let (w, h): (u32, u32) = window.inner_size().into();
            if let (Some(w), Some(h)) = (NonZeroU32::new(w), NonZeroU32::new(h)) {
                surface.resize(current, w, h);
            }
        }
    }

    /// The input of a frame of a window.
    fn input(&mut self, id: ViewportId) -> Option<egui::RawInput> {
        let infos: egui::ViewportIdMap<ViewportInfo> = self.viewports.iter().map(|(id, v)| (*id, v.info.clone())).collect();
        let viewport = self.viewports.get_mut(&id)?;
        let (Some(window), Some(state)) = (&viewport.window, &mut viewport.state) else { return None };
        egui_winit::update_viewport_info(&mut viewport.info, &self.ctx, window, false);
        let mut raw = state.take_egui_input(window);
        raw.viewports = infos;
        raw.viewports.insert(id, viewport.info.clone());
        raw.time = Some(self.started.elapsed().as_secs_f64());
        Some(raw)
    }

    /// After a pass: the windows it named are made or changed, and those
    /// it did not name are closed.
    fn outputs(&mut self, event_loop: Option<&ActiveEventLoop>, outputs: &egui::OrderedViewportIdMap<egui::ViewportOutput>) {
        for (id, output) in outputs {
            let ids = ViewportIdPair::from_self_and_parent(*id, output.parent);
            let viewport = self.viewports.entry(*id).or_insert_with(|| Viewport::new(ids, output.builder.clone()));
            viewport.ids = ids;
            let (mut changes, recreate) = viewport.builder.patch(output.builder.clone());
            if recreate {
                viewport.window = None;
                viewport.state = None;
                viewport.surface = None;
                if self.current_on == Some(*id) {
                    self.current_on = None;
                }
            }
            viewport.deferred.append(&mut changes);
            let old = viewport.window.as_ref().map(|w| w.inner_size());
            viewport.commands(&self.ctx, output.commands.clone());
            let new = viewport.window.as_ref().map(|w| w.inner_size());
            if old.is_some() && old != new {
                self.resize(*id);
            }
        }
        if let Some(event_loop) = event_loop {
            let missing: Vec<ViewportId> = self.viewports.iter().filter(|(_, v)| v.window.is_none() && outputs.get(&v.ids.this).is_some_and(|o| o.class == ViewportClass::Deferred)).map(|(id, _)| *id).collect();
            for id in missing {
                if let Err(err) = self.open(id, event_loop) {
                    eprintln!("paw-gui: a window could not open: {err:#}");
                }
            }
        }
        if let Some(on) = self.current_on
            && !outputs.contains_key(&on)
        {
            self.current_on = None;
        }
        self.viewports.retain(|id, _| outputs.contains_key(id));
        let viewports = &self.viewports;
        self.by_window.retain(|_, id| viewports.contains_key(id));
    }
}

/// The counts `PAW_GUI_STATS` prints every 10 seconds.
#[derive(Default)]
struct Stats {
    since: Option<Instant>,
    passes: u64,
    /// Frames made from the live values, with no pass.
    replays: u64,
    shown: u64,
    drawn_px: u64,
    rects: u64,
    changed_px: u64,
    uploads: u64,
    ages: [u64; 4],
}

impl Stats {
    /// Print the counts every 10 s; true when it did.
    fn report(&mut self, screen: [u32; 2]) -> bool {
        let Some(since) = self.since else { return false };
        let seconds = since.elapsed().as_secs_f64();
        if seconds < 10.0 {
            return false;
        }
        let shown = self.shown.max(1) as f64;
        let all = (screen[0] as f64 * screen[1] as f64).max(1.0);
        eprintln!(
            "paw-gui: stats: {} passes, {} frames without a pass, {} frames shown in {seconds:.1} s ({:.1}/s), {:.0} pixels drawn a frame ({:.1}% of the window) in {:.1} rectangles, {:.0} changed, {} uploads, buffer ages 0/1/2/3+: {:?}",
            self.passes,
            self.replays,
            self.shown,
            self.shown as f64 / seconds,
            self.drawn_px as f64 / shown,
            self.drawn_px as f64 / shown / all * 100.0,
            self.rects as f64 / shown,
            self.changed_px as f64 / shown,
            self.uploads,
            self.ages,
        );
        *self = Stats { since: Some(Instant::now()), ..Stats::default() };
        true
    }
}

/// What a frame is made from: egui's pass (its shapes, at its scale), or
/// the live parts of the last pass painted again (crate::live).
enum Frame {
    Pass(Vec<egui::epaint::ClippedShape>, f32),
    Live(Vec<(u32, Vec<egui::epaint::ClippedShape>)>),
}

/// The loop's state.
struct Runner {
    builder: ViewportBuilder,
    make: Option<Box<dyn FnOnce(&egui::Context, &GlInfo) -> Result<Box<dyn App>>>>,
    ctx: egui::Context,
    proxy: Arc<Mutex<EventLoopProxy<Wake>>>,
    gl: Option<Rc<RefCell<Gl>>>,
    app: Option<Box<dyn App>>,
    /// When each window is to be drawn next, and the redraws asked of
    /// winit and not come yet.
    next: HashMap<ViewportId, Instant>,
    asked: HashMap<ViewportId, Instant>,
    damage: Damage,
    stats: Stats,
    /// The main window has been shown (it starts hidden, until drawn).
    shown: bool,
    /// The window was uncovered (a redraw not asked for): all of it is
    /// shown again.
    exposed: bool,
    /// When the window was shown, and when all of it was last copied to it.
    shown_at: Option<Instant>,
    copied_all: Option<Instant>,
    closing: bool,
    failed: Option<anyhow::Error>,
    /// Frames may be made from the live values (crate::live): the last
    /// pass was drawn, and the damage keeps its shapes. What its input
    /// was, when egui asked to run again, and the frames made so in a row.
    replayable: bool,
    last_input: Option<(Option<egui::Rect>, bool)>,
    egui_due: Option<Instant>,
    in_a_row: u32,
    glyphs: crate::live::Glyphs,
}

thread_local! {
    /// The event loop while it hands out an event: a window of a view is
    /// made in the main window's pass, where it is not passed down.
    static EVENT_LOOP: Cell<*const ActiveEventLoop> = const { Cell::new(std::ptr::null()) };
}

/// Make the event loop reachable while `f` runs.
fn with_loop<R>(event_loop: &ActiveEventLoop, f: impl FnOnce() -> R) -> R {
    let before = EVENT_LOOP.replace(event_loop as *const _);
    let out = f();
    EVENT_LOOP.set(before);
    out
}

fn current_loop<R>(f: impl FnOnce(&ActiveEventLoop) -> R) -> Option<R> {
    let at = EVENT_LOOP.get();
    // SAFETY: set only while the event loop lends it, by `with_loop`.
    (!at.is_null()).then(|| f(unsafe { &*at }))
}

/// Run the window until it closes: `builder` describes the main window;
/// `make` makes the program once OpenGL is there.
pub fn run(builder: ViewportBuilder, make: impl FnOnce(&egui::Context, &GlInfo) -> Result<Box<dyn App>> + 'static) -> Result<()> {
    let event_loop = EventLoop::<Wake>::with_user_event().build()?;
    let ctx = egui::Context::default();
    ctx.set_embed_viewports(false);
    ctx.options_mut(|o| o.max_passes = std::num::NonZeroUsize::new(2).unwrap());
    let proxy = Arc::new(Mutex::new(event_loop.create_proxy()));
    {
        let proxy = proxy.clone();
        ctx.set_request_repaint_callback(move |info| {
            if let Ok(proxy) = proxy.lock() {
                let _ = proxy.send_event(Wake { viewport: info.viewport_id, when: Instant::now() + info.delay, pass: info.current_cumulative_pass_nr, direct: false });
            }
        });
    }
    let mut runner = Runner {
        builder,
        make: Some(Box::new(make)),
        ctx,
        proxy,
        gl: None,
        app: None,
        next: HashMap::new(),
        asked: HashMap::new(),
        damage: Damage::default(),
        stats: Stats { since: std::env::var_os("PAW_GUI_STATS").map(|_| Instant::now()), ..Stats::default() },
        shown: false,
        exposed: false,
        shown_at: None,
        copied_all: None,
        closing: false,
        failed: None,
        replayable: false,
        last_input: None,
        egui_due: None,
        in_a_row: 0,
        glyphs: crate::live::Glyphs::default(),
    };
    event_loop.run_app(&mut runner)?;
    let _ = &runner.proxy;
    match runner.failed.take() {
        Some(err) => Err(err),
        None => Ok(()),
    }
}

impl Runner {
    /// OpenGL, the main window, and the program.
    fn start(&mut self, event_loop: &ActiveEventLoop) -> Result<()> {
        let mut builder = self.builder.clone().with_visible(false);
        // No larger than the screen, as eframe kept it.
        if let (Some(size), Some(monitor)) = (builder.inner_size, event_loop.primary_monitor().or_else(|| event_loop.available_monitors().next())) {
            let screen = monitor.size().to_logical::<f32>(monitor.scale_factor());
            builder.inner_size = Some(egui::vec2(size.x.min(screen.width), size.y.min(screen.height)));
        }
        let (window, config) = self.open_window(event_loop, &builder)?;
        let context = Self::create_context(&config, &window)?;
        // On Wayland the compositor's calls to draw pace the frames; a
        // swap that waits would only hang a hidden window.
        let wayland = matches!(event_loop.display_handle()?.as_raw(), RawDisplayHandle::Wayland(_));
        let swap_interval = if wayland { SwapInterval::DontWait } else { SwapInterval::Wait(NonZeroU32::MIN) };
        let mut info = ViewportInfo::default();
        egui_winit::update_viewport_info(&mut info, &self.ctx, &window, true);
        let ppp = egui_winit::pixels_per_point(&self.ctx, &window);
        self.ctx.input_mut(|i| {
            i.raw.viewports.insert(ViewportId::ROOT, info.clone());
            i.pixels_per_point = ppp;
        });
        // The main window's surface, and the context current on it: glow
        // asks OpenGL its version when it starts.
        let (w, h): (u32, u32) = window.inner_size().into();
        let attributes = SurfaceAttributesBuilder::<WindowSurface>::new().build(
            window.window_handle()?.as_raw(),
            NonZeroU32::new(w).unwrap_or(NonZeroU32::MIN),
            NonZeroU32::new(h).unwrap_or(NonZeroU32::MIN),
        );
        let surface = unsafe { config.display().create_window_surface(&config, &attributes)? };
        let current = context.make_current(&surface)?;
        let copy_sub = copy_sub_buffer(&config, &surface);
        if let Err(err) = surface.set_swap_interval(&current, swap_interval) {
            eprintln!("paw-gui: the swap interval: {err}");
        }
        let mut root = Viewport::new(ViewportIdPair::ROOT, builder);
        root.info = info;
        root.window = Some(Arc::new(window));
        root.surface = Some(surface);
        let display = config.display();
        let gl = unsafe {
            glow::Context::from_loader_function(|name| {
                let name = std::ffi::CString::new(name).unwrap_or_default();
                display.get_proc_address(&name)
            })
        };
        let painter = egui_glow::Painter::new(Arc::new(gl), "", None, true).map_err(|err| anyhow!("{err}"))?;
        let mut gl = Gl {
            ctx: self.ctx.clone(),
            config,
            swap_interval,
            current: Some(current),
            not_current: None,
            current_on: Some(ViewportId::ROOT),
            painter,
            viewports: HashMap::from([(ViewportId::ROOT, root)]),
            by_window: HashMap::new(),
            started: Instant::now(),
            copy_sub,
        };
        gl.open(ViewportId::ROOT, event_loop)?;
        let info = unsafe {
            let raw = gl.painter.gl();
            let proxy = self.proxy.clone();
            let wake = move || {
                if let Ok(proxy) = proxy.lock() {
                    let _ = proxy.send_event(Wake { viewport: ViewportId::ROOT, when: Instant::now(), pass: 0, direct: true });
                }
            };
            GlInfo { renderer: raw.get_parameter_string(glow::RENDERER), version: raw.get_parameter_string(glow::VERSION), wake: Arc::new(wake) }
        };
        let gl = Rc::new(RefCell::new(gl));
        {
            let gl = Rc::downgrade(&gl);
            egui::Context::set_immediate_viewport_renderer(move |ctx, viewport| {
                if let Some(gl) = gl.upgrade() {
                    immediate(ctx, &gl, viewport);
                }
            });
        }
        self.gl = Some(gl);
        let make = self.make.take().context("started twice")?;
        self.app = Some(make(&self.ctx, &info)?);
        self.next.insert(ViewportId::ROOT, Instant::now());
        Ok(())
    }

    /// The main window and the OpenGL configuration it was made with.
    fn open_window(&self, event_loop: &ActiveEventLoop, builder: &ViewportBuilder) -> Result<(Window, Config)> {
        let attributes = egui_winit::create_winit_window_attributes(&self.ctx, builder.clone());
        let template = ConfigTemplateBuilder::new().prefer_hardware_accelerated(None).with_depth_size(0).with_stencil_size(0).with_transparency(false);
        // EGL first: it says how old a buffer is and shows only what changed.
        // On X11 on the processor GLX first: it copies the changed parts to
        // the window through shared memory (GLX_MESA_copy_sub_buffer), where
        // Mesa's EGL puts the whole window to the X server each frame.
        let x11 = matches!(event_loop.display_handle()?.as_raw(), RawDisplayHandle::Xlib(_) | RawDisplayHandle::Xcb(_));
        let software = std::env::var_os("LIBGL_ALWAYS_SOFTWARE").is_some_and(|v| !v.is_empty() && v != "0");
        let preference = if x11 && software { glutin_winit::ApiPreference::FallbackEgl } else { glutin_winit::ApiPreference::PreferEgl };
        let (window, config) = glutin_winit::DisplayBuilder::new()
            .with_preference(preference)
            .with_window_attributes(Some(attributes))
            .build(event_loop, template, |mut configs| configs.next().expect("an OpenGL configuration"))
            .map_err(|err| anyhow!("{err}"))?;
        let window = window.context("no window")?;
        egui_winit::apply_viewport_builder_to_window(&self.ctx, &window, builder);
        Ok((window, config))
    }

    /// An OpenGL context for the window: the desktop's, else GLES, else the compatibility profile.
    fn create_context(config: &Config, window: &Window) -> Result<NotCurrentContext> {
        let handle = Some(window.window_handle()?.as_raw());
        let tries = [
            ContextAttributesBuilder::new().build(handle),
            ContextAttributesBuilder::new().with_context_api(ContextApi::Gles(None)).build(handle),
            ContextAttributesBuilder::new().with_profile(GlProfile::Compatibility).build(handle),
        ];
        let mut context = Err(anyhow!("no OpenGL context"));
        for attributes in &tries {
            match unsafe { config.display().create_context(&config, attributes) } {
                Ok(made) => {
                    context = Ok(made);
                    break;
                }
                Err(err) => context = Err(anyhow!("{err}")),
            }
        }
        context
    }

    /// A pass of the main window, and its frame where it changed.
    fn frame(&mut self, event_loop: &ActiveEventLoop, draw: bool) {
        let (Some(gl), Some(app)) = (self.gl.clone(), self.app.as_mut()) else { return };
        self.asked.remove(&ViewportId::ROOT);
        let Some(mut raw) = gl.borrow_mut().input(ViewportId::ROOT) else { return };
        // Nothing but the live values moved: the frame is the last pass's,
        // with its live parts painted again.
        let input = (raw.screen_rect, raw.focused);
        let replay = draw
            && self.replayable
            && self.shown
            && !self.exposed
            && self.in_a_row < crate::live::MOST_IN_A_ROW
            && self.last_input == Some(input)
            && !raw.viewport().close_requested()
            && self.egui_due.is_none_or(|at| Instant::now() < at)
            && gl.borrow().viewports.len() == 1;
        if replay
            && let Some(parts) = app.replay(&self.ctx, &raw)
            && self.glyphs.know(&parts)
        {
            self.in_a_row += 1;
            self.stats.replays += 1;
            let partial = app.partial();
            let clear = app.clear_color();
            let mut gl = gl.borrow_mut();
            self.paint(&mut gl, Frame::Live(parts), &mut egui::TexturesDelta::default(), partial, clear);
            self.report(&gl);
            return;
        }
        self.in_a_row = 0;
        self.last_input = Some(input);
        app.raw_input_hook(&self.ctx, &mut raw);
        let close = raw.viewport().close_requested();
        // The program's pass: it may draw the views in windows of their own.
        let output = self.ctx.run_ui(raw, |ui| app.ui(ui));
        self.stats.passes += 1;
        if close && !output.viewport_output.get(&ViewportId::ROOT).is_some_and(|o| o.commands.contains(&ViewportCommand::CancelClose)) {
            self.closing = true;
        }
        let partial = app.partial();
        let clear = app.clear_color();
        let mut gl = gl.borrow_mut();
        let gl = &mut *gl;
        if let Some(root) = gl.viewports.get_mut(&ViewportId::ROOT) {
            root.info.events.clear();
            if let (Some(window), Some(state)) = (&root.window, &mut root.state) {
                state.handle_platform_output(window, output.platform_output);
            }
        }
        let mut delta = output.textures_delta;
        self.stats.uploads += delta.set.len() as u64;
        // When egui asked to run again (an animation, a hint's delay, the
        // program's own timers): no frame is made without a pass from then.
        let delay = output.viewport_output.get(&ViewportId::ROOT).map_or(Duration::MAX, |o| o.repaint_delay);
        self.egui_due = (delay < Duration::from_secs(3600)).then(|| Instant::now() + delay);
        self.replayable = false;
        if draw {
            self.glyphs.learn(&output.shapes);
            self.paint(gl, Frame::Pass(output.shapes, output.pixels_per_point), &mut delta, partial, clear);
        }
        // Textures not drawn with are set (and let go) all the same.
        for (id, images) in delta.set.drain() {
            for image in images {
                gl.painter.set_texture(id, &image);
            }
        }
        for id in delta.free.drain() {
            gl.painter.free_texture(id);
        }
        gl.outputs(Some(event_loop), &output.viewport_output);
        self.report(gl);
        if self.closing {
            event_loop.exit();
        }
    }

    /// The counts, every 10 seconds with `PAW_GUI_STATS`.
    fn report(&mut self, gl: &Gl) {
        let screen = gl.viewports.get(&ViewportId::ROOT).and_then(|v| v.window.as_ref()).map_or([0, 0], |w| w.inner_size().into());
        if self.stats.report(screen) {
            let passes = self.damage.passes.max(1);
            eprintln!(
                "paw-gui: stats: {:.0} shapes a pass, in {:.0} places in squares",
                self.damage.counted as f64 / passes as f64,
                self.damage.pushes as f64 / passes as f64
            );
            (self.damage.counted, self.damage.pushes, self.damage.passes) = (0, 0, 0);
        }
    }

    /// Draw what changed of the main window, onto the buffer as the driver
    /// gives it back, and show it.
    fn paint(&mut self, gl: &mut Gl, frame: Frame, delta: &mut egui::TexturesDelta, partial: bool, clear: [f32; 4]) {
        let Some(window) = gl.viewports.get(&ViewportId::ROOT).and_then(|v| v.window.clone()) else { return };
        let screen: [u32; 2] = window.inner_size().into();
        if screen[0] == 0 || screen[1] == 0 {
            return;
        }
        let (changed, ppp, all) = match frame {
            Frame::Pass(shapes, ppp) => {
                // A picture given new pixels is drawn again where it shows; the
                // font's texture made anew changes all the text.
                let font = egui::TextureId::default();
                let fonts_anew = delta.set.iter().any(|(id, images)| *id == font && images.iter().any(|image| image.pos.is_none()));
                let textures: HashSet<egui::TextureId> = delta.set.iter().map(|(id, _)| *id).filter(|id| *id != font).collect();
                let all = !partial || !self.shown || fonts_anew || std::mem::take(&mut self.exposed);
                let changed = self.damage.frame(shapes, ppp, screen, &textures, all);
                self.replayable = true;
                (changed, ppp, all)
            }
            Frame::Live(parts) => {
                if screen != self.damage.screen() {
                    self.replayable = false;
                    return;
                }
                (self.damage.replay(parts, !partial), self.damage.ppp(), !partial)
            }
        };
        if !changed {
            return;
        }
        if gl.current(ViewportId::ROOT).is_err() {
            return;
        }
        let Some(surface) = gl.viewports.get(&ViewportId::ROOT).and_then(|v| v.surface.as_ref()) else { return };
        // Copied, not swapped: the buffer is always the last frame.
        let age = if all { 0 } else if gl.copy_sub.is_some() { 1 } else { surface.buffer_age() };
        self.stats.ages[(age as usize).min(3)] += 1;
        let rects = self.damage.to_draw(age);
        let changed = self.damage.changed();
        self.draw_rects(gl, screen, ppp, &rects, clear, delta);
        self.stats.changed_px += changed.iter().map(|r| ((r[2] - r[0]) * (r[3] - r[1])) as u64).sum::<u64>();
        self.show(gl, &window, screen, all, changed);
    }

    /// Clear each rectangle and draw into it the shapes that reach it.
    fn draw_rects(&mut self, gl: &mut Gl, screen: [u32; 2], ppp: f32, rects: &[Px], clear: [f32; 4], delta: &mut egui::TexturesDelta) {
        let raw = gl.painter.gl().clone();
        // The rectangles do not overlap: each is cleared, and each gets the
        // shapes that reach into it, cut to it; all are drawn at once.
        let mut primitives = Vec::new();
        for rect in rects {
            unsafe {
                raw.enable(glow::SCISSOR_TEST);
                raw.scissor(rect[0], screen[1] as i32 - rect[3], rect[2] - rect[0], rect[3] - rect[1]);
                raw.color_mask(true, true, true, true);
                raw.clear_color(clear[0], clear[1], clear[2], clear[3]);
                raw.clear(glow::COLOR_BUFFER_BIT);
            }
            let cut = egui::Rect::from_min_max(egui::pos2(rect[0] as f32, rect[1] as f32) / ppp, egui::pos2(rect[2] as f32, rect[3] as f32) / ppp);
            let mut some = self.ctx.tessellate(self.damage.shapes_in(*rect), ppp);
            some.retain_mut(|p| {
                p.clip_rect = p.clip_rect.intersect(cut);
                p.clip_rect.is_positive()
            });
            primitives.append(&mut some);
            self.stats.drawn_px += ((rect[2] - rect[0]) * (rect[3] - rect[1])) as u64;
            self.stats.rects += 1;
        }
        gl.painter.paint_and_update_textures(screen, ppp, &primitives, delta);
    }

    /// Show what changed of the buffer, where the platform lets it say so,
    /// else the whole of it.
    fn show(&mut self, gl: &mut Gl, window: &Window, screen: [u32; 2], all: bool, changed: Vec<Px>) {
        // Shown: only what changed, where the platform lets it say so.
        if let Some(copy) = &gl.copy_sub {
            let h = screen[1] as i32;
            // All of it now and then, and for a second after it is shown: what
            // an X server without a compositor lost of a covered window, or
            // of one not yet mapped, comes back.
            let refresh = self.copied_all.is_none_or(|at| at.elapsed() > Duration::from_secs(1));
            if all || refresh {
                self.copied_all = Some(Instant::now()).filter(|_| self.shown_at.is_some_and(|at| at.elapsed() > Duration::from_secs(1)));
            }
            let parts = if all || refresh { vec![[0, 0, screen[0] as i32, h]] } else { changed };
            for r in parts {
                unsafe { (copy.copy)(copy.display, copy.drawable, r[0], h - r[3], r[2] - r[0], r[3] - r[1]) };
            }
            self.damage.shown();
            self.stats.shown += 1;
            if !self.shown {
                self.shown = true;
                window.set_visible(true);
                self.shown_at = Some(Instant::now());
            }
            return;
        }
        window.pre_present_notify();
        let Some(current) = &gl.current else { return };
        let surface = gl.viewports[&ViewportId::ROOT].surface.as_ref().unwrap();
        let swapped = match surface {
            Surface::Egl(egl) if !all => {
                let h = screen[1] as i32;
                let damage: Vec<glutin::surface::Rect> = changed.iter().map(|r| glutin::surface::Rect::new(r[0], h - r[3], r[2] - r[0], r[3] - r[1])).collect();
                match current {
                    glutin::context::PossiblyCurrentContext::Egl(context) => egl.swap_buffers_with_damage(context, &damage),
                    #[allow(unreachable_patterns)]
                    _ => surface.swap_buffers(current),
                }
            }
            _ => surface.swap_buffers(current),
        };
        if let Err(err) = swapped {
            eprintln!("paw-gui: showing the frame: {err}");
        }
        self.damage.shown();
        self.stats.shown += 1;
        if !self.shown {
            self.shown = true;
            window.set_visible(true);
        }
    }

    /// Ask for a frame of a window at a time: a view in a window of its own
    /// is drawn in the main window's pass.
    fn wake(&mut self, viewport: ViewportId, when: Instant) {
        let root = match &self.gl {
            Some(gl) => gl.borrow().viewports.get(&viewport).map_or(ViewportId::ROOT, |v| if v.ids.this == ViewportId::ROOT { v.ids.this } else { v.ids.parent }),
            None => ViewportId::ROOT,
        };
        let at = self.next.entry(root).or_insert(when);
        *at = (*at).min(when);
    }

    /// Ask winit for the frames due, and sleep until the next.
    fn schedule(&mut self, event_loop: &ActiveEventLoop) {
        let now = Instant::now();
        let due: Vec<ViewportId> = self.next.iter().filter(|(_, at)| **at <= now).map(|(id, _)| *id).collect();
        for id in due {
            self.next.remove(&id);
            let window = self.gl.as_ref().and_then(|gl| gl.borrow().viewports.get(&id).and_then(|v| v.window.clone()));
            if let Some(window) = window {
                window.request_redraw();
                self.asked.entry(id).or_insert(now + MISSED_REDRAW);
            }
        }
        // A redraw the compositor withholds (a hidden window on Wayland):
        // the pass runs, so that the program goes on, but nothing is drawn.
        let late: Vec<ViewportId> = self.asked.iter().filter(|(_, at)| **at <= now).map(|(id, _)| *id).collect();
        for id in late {
            self.asked.remove(&id);
            if id == ViewportId::ROOT {
                with_loop(event_loop, || self.frame(event_loop, false));
            }
        }
        let next = self.next.values().chain(self.asked.values()).min().copied();
        event_loop.set_control_flow(match next {
            Some(at) => ControlFlow::WaitUntil(at),
            None => ControlFlow::Wait,
        });
    }
}

impl ApplicationHandler<Wake> for Runner {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.gl.is_some() || self.failed.is_some() {
            return;
        }
        if let Err(err) = with_loop(event_loop, || self.start(event_loop)) {
            self.failed = Some(err);
            event_loop.exit();
            return;
        }
        self.schedule(event_loop);
    }

    fn user_event(&mut self, event_loop: &ActiveEventLoop, wake: Wake) {
        let pass = self.ctx.cumulative_pass_nr_for(wake.viewport);
        // A request made before the frame that answered it is old.
        if wake.direct || pass == wake.pass || pass == wake.pass + 1 {
            self.wake(wake.viewport, wake.when);
        }
        self.schedule(event_loop);
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, window_id: WindowId, event: WindowEvent) {
        let Some(gl) = self.gl.clone() else { return };
        let Some(id) = gl.borrow().by_window.get(&window_id).copied() else { return };
        match &event {
            WindowEvent::RedrawRequested => {
                if id == ViewportId::ROOT {
                    self.exposed |= !self.asked.contains_key(&ViewportId::ROOT);
                    with_loop(event_loop, || self.frame(event_loop, true));
                } else {
                    self.wake(id, Instant::now());
                }
                self.schedule(event_loop);
                return;
            }
            WindowEvent::Resized(size) if size.width > 0 && size.height > 0 => {
                gl.borrow_mut().resize(id);
                self.wake(id, Instant::now());
            }
            WindowEvent::CloseRequested => {
                if id == ViewportId::ROOT && self.closing {
                    event_loop.exit();
                    return;
                }
                if let Some(viewport) = gl.borrow_mut().viewports.get_mut(&id) {
                    viewport.info.events.push(egui::ViewportEvent::Close);
                }
                self.wake(id, Instant::now());
            }
            WindowEvent::Occluded(occluded) => {
                if let Some(viewport) = gl.borrow_mut().viewports.get_mut(&id) {
                    viewport.info.occluded = Some(*occluded);
                }
            }
            _ => {}
        }
        let response = {
            let mut gl = gl.borrow_mut();
            let Some(viewport) = gl.viewports.get_mut(&id) else { return };
            match (&viewport.window, &mut viewport.state) {
                (Some(window), Some(state)) => state.on_window_event(window, &event),
                _ => return,
            }
        };
        if response.repaint {
            self.wake(id, Instant::now());
        }
        self.schedule(event_loop);
    }

    fn device_event(&mut self, _event_loop: &ActiveEventLoop, _device: winit::event::DeviceId, _event: winit::event::DeviceEvent) {}

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        self.schedule(event_loop);
    }

    fn exiting(&mut self, _event_loop: &ActiveEventLoop) {
        if let Some(mut app) = self.app.take() {
            app.on_exit();
        }
        if let Some(gl) = self.gl.take() {
            let mut gl = gl.borrow_mut();
            let _ = gl.current(ViewportId::ROOT);
            gl.painter.destroy();
            gl.viewports.clear();
        }
    }
}

/// Draw a view's window of its own, whole, in the main window's pass.
fn immediate(ctx: &egui::Context, gl: &RefCell<Gl>, viewport: egui::ImmediateViewport<'_>) {
    let egui::ImmediateViewport { ids, builder, mut viewport_ui_cb } = viewport;
    let id = ids.this;
    {
        let mut gl = gl.borrow_mut();
        let entry = gl.viewports.entry(id).or_insert_with(|| Viewport::new(ids, builder.clone()));
        entry.ids = ids;
        let (mut changes, recreate) = entry.builder.patch(builder);
        if recreate {
            entry.window = None;
            entry.state = None;
            entry.surface = None;
        }
        entry.deferred.append(&mut changes);
        let opened = current_loop(|event_loop| gl.open(id, event_loop));
        if let Some(Err(err)) = opened {
            eprintln!("paw-gui: a window could not open: {err:#}");
            return;
        }
    }
    let Some(input) = gl.borrow_mut().input(id) else { return };
    // The program's code for the window: no borrow is held, it may come back here.
    let output = ctx.run_ui(input, |ui| viewport_ui_cb(ui));
    let primitives = ctx.tessellate(output.shapes, output.pixels_per_point);
    let mut gl = gl.borrow_mut();
    let gl = &mut *gl;
    if let Some(viewport) = gl.viewports.get_mut(&id) {
        viewport.info.events.clear();
    }
    let mut delta = output.textures_delta;
    if gl.current(id).is_ok()
        && let Some(viewport) = gl.viewports.get(&id)
        && let (Some(window), Some(surface)) = (&viewport.window, &viewport.surface)
    {
        let screen: [u32; 2] = window.inner_size().into();
        egui_glow::painter::clear(gl.painter.gl(), screen, [0.0, 0.0, 0.0, 0.0]);
        gl.painter.paint_and_update_textures(screen, output.pixels_per_point, &primitives, &mut delta);
        window.pre_present_notify();
        if let Some(current) = &gl.current
            && let Err(err) = surface.swap_buffers(current)
        {
            eprintln!("paw-gui: showing a window: {err}");
        }
    }
    for (texture, images) in delta.set.drain() {
        for image in images {
            gl.painter.set_texture(texture, &image);
        }
    }
    for texture in delta.free.drain() {
        gl.painter.free_texture(texture);
    }
    if let Some(viewport) = gl.viewports.get_mut(&id)
        && let (Some(window), Some(state)) = (&viewport.window, &mut viewport.state)
    {
        state.handle_platform_output(window, output.platform_output);
    }
    for (vid, out) in &output.viewport_output {
        if let Some(viewport) = gl.viewports.get_mut(vid) {
            viewport.commands(&gl.ctx, out.commands.clone());
        }
    }
}
