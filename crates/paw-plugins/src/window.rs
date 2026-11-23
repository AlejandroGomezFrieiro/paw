//! Windows for plugin editors, and the small event loop plugins expect a host
//! to run for them.
//!
//! Plugin editors on Linux draw into an X11 window the host provides. The host
//! window here is a plain top-level window with nothing in it; the plugin
//! creates its own child inside. On a Wayland desktop this goes through
//! XWayland, like every other X11 program.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::ffi::{CStr, c_char, c_void};
use std::os::fd::RawFd;
use std::ptr;
use std::rc::Rc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use x11rb::connection::Connection;
use x11rb::properties::WmSizeHints;
use x11rb::protocol::Event;
use x11rb::protocol::xproto::{
    AtomEnum, ConfigureWindowAux, ConnectionExt as _, CreateWindowAux, EventMask, PropMode,
    WindowClass,
};
use x11rb::rust_connection::RustConnection;
use x11rb::wrapper::ConnectionExt as _;

pub(crate) enum WindowEvent {
    /// The user closed the window.
    Closed,
    Resized(u32, u32),
}

/// The connection to the X server, shared by every editor window.
struct Display {
    conn: RustConnection,
    root: u32,
    black: u32,
    wm_protocols: u32,
    wm_delete: u32,
    net_wm_name: u32,
    utf8_string: u32,
    /// Events read off the connection, waiting for their window to ask.
    events: RefCell<HashMap<u32, Vec<WindowEvent>>>,
}

thread_local! {
    static DISPLAY: RefCell<Option<Rc<Display>>> = const { RefCell::new(None) };
}

/// Why the X display cannot be reached, in terms of what to do about it.
fn why_unreachable() -> String {
    let Some(display) = std::env::var_os("DISPLAY").filter(|d| !d.is_empty()) else {
        return "plugin windows need an X display, and DISPLAY is not set here: \
                start from a terminal on the desktop"
            .into();
    };
    let display = display.to_string_lossy();
    match std::env::var_os("XAUTHORITY").map(std::path::PathBuf::from) {
        Some(file) if !file.exists() => format!(
            "plugin windows cannot reach the X display {display}: this terminal is older than \
             the display it names (its XAUTHORITY, {}, is gone); open a new terminal",
            file.display()
        ),
        _ => format!("plugin windows cannot reach the X display {display}"),
    }
}

/// Make the display reachable from a terminal that has outlived it.
///
/// A display that is restarted gets a new authority file, and a terminal
/// (or a multiplexer session) started before that still names the old one in
/// `XAUTHORITY`: every X program started from it is then turned away. When
/// the file named is gone, look for the one the display uses now, in the
/// places desktops keep them, and put the first that lets us in into the
/// environment, where plugins look for it too when they open their windows.
///
/// `home` is the user's home folder, where `~/.Xauthority` is: the program
/// gives `$HOME`. Returns what it changed, for the log.
///
/// # Safety
///
/// It changes the environment: call it before any other thread starts
/// (in this process, or in a library it loaded), while nothing else can
/// read or write the environment at the same time.
pub unsafe fn repair_display_env(home: Option<&std::path::Path>) -> Option<String> {
    std::env::var_os("DISPLAY").filter(|d| !d.is_empty())?;
    let stale = std::env::var_os("XAUTHORITY").map(std::path::PathBuf::from);
    match &stale {
        Some(file) if file.exists() => return None,
        Some(_) => {}
        // With none named the default is used, if there is one.
        None => {
            if home?.join(".Xauthority").exists() || x11rb::connect(None).is_ok() {
                return None;
            }
        }
    }
    let mut candidates: Vec<(std::time::SystemTime, std::path::PathBuf)> = Vec::new();
    if let Some(runtime) = std::env::var_os("XDG_RUNTIME_DIR") {
        for entry in std::fs::read_dir(runtime).into_iter().flatten().flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with("xauth_") || name.starts_with(".mutter-Xwaylandauth") {
                let modified = entry.metadata().and_then(|m| m.modified()).ok();
                candidates.push((modified.unwrap_or(std::time::UNIX_EPOCH), entry.path()));
            }
        }
    }
    // The newest first: it belongs to the display that is running now.
    candidates.sort_by_key(|candidate| std::cmp::Reverse(candidate.0));
    if let Some(home) = home {
        candidates.push((std::time::UNIX_EPOCH, home.join(".Xauthority")));
    }
    for (_, file) in candidates.into_iter().filter(|(_, file)| file.exists()) {
        // SAFETY: No other thread is running yet, as the caller of this `unsafe fn` promised, so
        // nothing reads or writes the environment at the same time.
        unsafe { std::env::set_var("XAUTHORITY", &file) };
        if x11rb::connect(None).is_ok() {
            return Some(format!(
                "this terminal named an X authority file that is gone ({}); using {} instead",
                stale
                    .as_ref()
                    .map_or("none".into(), |f| f.display().to_string()),
                file.display()
            ));
        }
    }
    match stale {
        // SAFETY: As above: no other thread is running yet, as the caller promised.
        Some(file) => unsafe { std::env::set_var("XAUTHORITY", file) },
        // SAFETY: As above: no other thread is running yet, as the caller promised.
        None => unsafe { std::env::remove_var("XAUTHORITY") },
    }
    None
}

fn display() -> Result<Rc<Display>> {
    DISPLAY.with(|slot| {
        if let Some(display) = slot.borrow().as_ref() {
            return Ok(display.clone());
        }
        let (conn, screen) = x11rb::connect(None).with_context(why_unreachable)?;
        let atom =
            |name: &[u8]| -> Result<u32> { Ok(conn.intern_atom(false, name)?.reply()?.atom) };
        let display = Rc::new(Display {
            root: conn.setup().roots[screen].root,
            black: conn.setup().roots[screen].black_pixel,
            wm_protocols: atom(b"WM_PROTOCOLS")?,
            wm_delete: atom(b"WM_DELETE_WINDOW")?,
            net_wm_name: atom(b"_NET_WM_NAME")?,
            utf8_string: atom(b"UTF8_STRING")?,
            events: RefCell::new(HashMap::new()),
            conn,
        });
        *slot.borrow_mut() = Some(display.clone());
        Ok(display)
    })
}

impl Display {
    /// Read whatever the server has sent and file it under its window.
    fn pump(&self) {
        let mut events = self.events.borrow_mut();
        while let Ok(Some(event)) = self.conn.poll_for_event() {
            match event {
                Event::ClientMessage(e) if e.data.as_data32()[0] == self.wm_delete => {
                    events
                        .entry(e.window)
                        .or_default()
                        .push(WindowEvent::Closed);
                }
                Event::ConfigureNotify(e) => {
                    let size = WindowEvent::Resized(e.width as u32, e.height as u32);
                    events.entry(e.window).or_default().push(size);
                }
                _ => {}
            }
        }
    }
}

/// Keep a plugin's X11 mistakes from ending the program.
///
/// Plugins talk to the X server through Xlib, whose default reaction to any
/// protocol error is to exit the process. Applications replace that handler;
/// plugins leave it to the host. This host does not use Xlib itself, so it
/// looks the function up in the copy the plugin brought with it.
fn tolerate_x_errors() {
    unsafe extern "C" fn ignore(
        _display: *mut std::ffi::c_void,
        _error: *mut std::ffi::c_void,
    ) -> i32 {
        0
    }
    type Handler = unsafe extern "C" fn(*mut std::ffi::c_void, *mut std::ffi::c_void) -> i32;
    // SAFETY: The library is opened by name, so this is the Xlib the plugin already loaded (or the
    // system's); `XSetErrorHandler` has the signature `Handler` by the Xlib ABI, and `ignore`
    // matches `Handler`. The library is forgotten, not closed, so `ignore` and the symbol stay valid.
    unsafe {
        // Opening by name finds the library a plugin has already loaded.
        let Ok(xlib) = libloading::Library::new("libX11.so.6") else {
            return;
        };
        if let Ok(set_handler) =
            xlib.get::<unsafe extern "C" fn(Handler) -> Option<Handler>>(b"XSetErrorHandler\0")
        {
            set_handler(ignore);
        }
        std::mem::forget(xlib);
    }
}

/// How much plugin editors should magnify themselves: 1 on an ordinary
/// screen, 2 on one with twice the pixel density.
///
/// X11 has no per-window scale, and plugins that are not told draw at 1 and
/// come out tiny or blurred on a dense screen. Desktops publish the scale as
/// the `Xft.dpi` resource (96 is 1), which a Wayland compositor also sets for
/// its X11 programs when it lets them scale themselves. `PAW_UI_SCALE`
/// overrides it.
pub(crate) fn ui_scale() -> f64 {
    static SCALE: OnceLock<f64> = OnceLock::new();
    *SCALE.get_or_init(|| {
        let from_env = std::env::var("PAW_UI_SCALE")
            .ok()
            .and_then(|text| text.parse::<f64>().ok());
        let from_x = || {
            let display = display().ok()?;
            let reply = display
                .conn
                .get_property(
                    false,
                    display.root,
                    AtomEnum::RESOURCE_MANAGER,
                    AtomEnum::STRING,
                    0,
                    1 << 20,
                )
                .ok()?
                .reply()
                .ok()?;
            let resources = String::from_utf8_lossy(&reply.value).into_owned();
            let dpi = resources
                .lines()
                .find_map(|line| line.strip_prefix("Xft.dpi:"))?;
            Some(dpi.trim().parse::<f64>().ok()? / 96.0)
        };
        from_env
            .or_else(from_x)
            .filter(|scale| scale.is_finite())
            .unwrap_or(1.0)
            .clamp(0.5, 4.0)
    })
}

/// A Gtk window around a plugin editor that is a bare Gtk widget.
///
/// The host links no toolkit. The editor's library brings Gtk in with it, and
/// the dozen functions needed are looked up in that copy, which is also the
/// only one the widget can live in: Gtk 2 for a Gtk 2 editor, Gtk 3 for a
/// Gtk 3 one. Gtk 3 windows are native Wayland windows.
pub(crate) struct GtkWindow {
    gtk: Gtk,
    window: *mut c_void,
    widget: *mut c_void,
    closed: Box<Cell<bool>>,
}

type GtkObject = *mut c_void;

#[derive(Clone, Copy)]
struct Gtk {
    container_remove: unsafe extern "C" fn(GtkObject, GtkObject),
    widget_destroy: unsafe extern "C" fn(GtkObject),
    events_pending: unsafe extern "C" fn() -> i32,
    main_iteration_do: unsafe extern "C" fn(i32) -> i32,
    object_unref: unsafe extern "C" fn(GtkObject),
}

impl GtkWindow {
    /// Put `widget` in a new window and show it.
    ///
    /// # Safety
    /// `widget` must be a `GtkWidget` made by a library already loaded into
    /// this process.
    pub(crate) unsafe fn wrap(widget: *mut c_void, title: &CStr) -> Result<Self> {
        use libloading::os::unix::{Library, RTLD_LAZY};
        if widget.is_null() {
            anyhow::bail!("the editor gave back no widget");
        }
        // SAFETY: `widget` is a `GtkWidget` of a library already loaded (the caller's promise on `wrap`), and
        // the library is opened with RTLD_NOLOAD so it is that same copy. Each symbol is looked up by
        // the name of a Gtk function whose C signature is the type given, and the library is held in
        // ManuallyDrop so the copied function pointers stay valid. Gtk is called from the thread that
        // made the window, with the window and widget made here; `closed` is a Box that the window owns
        // and that lives past the signal handler, which `widget_destroy` ends in Drop.
        unsafe {
            // Only a copy that is already loaded: the one the editor uses.
            let lib = ["libgtk-3.so.0", "libgtk-x11-2.0.so.0"]
                .iter()
                .find_map(|name| Library::open(Some(name), RTLD_LAZY | libc::RTLD_NOLOAD).ok())
                .context("the editor's Gtk library is not loaded")?;
            let lib = std::mem::ManuallyDrop::new(lib);
            macro_rules! symbol {
                ($name:literal: $ty:ty) => {
                    *lib.get::<$ty>($name)
                        .context(concat!("Gtk lacks ", stringify!($name)))?
                };
            }
            let init = symbol!(b"gtk_init_check\0": unsafe extern "C" fn(*mut i32, *mut *mut *mut c_char) -> i32);
            let window_new = symbol!(b"gtk_window_new\0": unsafe extern "C" fn(i32) -> GtkObject);
            let set_title =
                symbol!(b"gtk_window_set_title\0": unsafe extern "C" fn(GtkObject, *const c_char));
            let container_add =
                symbol!(b"gtk_container_add\0": unsafe extern "C" fn(GtkObject, GtkObject));
            let show_all = symbol!(b"gtk_widget_show_all\0": unsafe extern "C" fn(GtkObject));
            let object_ref =
                symbol!(b"g_object_ref\0": unsafe extern "C" fn(GtkObject) -> GtkObject);
            let connect = symbol!(b"g_signal_connect_data\0": unsafe extern "C" fn(GtkObject, *const c_char, *const c_void, *mut c_void, *const c_void, i32) -> u64);
            let gtk = Gtk {
                container_remove: symbol!(b"gtk_container_remove\0": unsafe extern "C" fn(GtkObject, GtkObject)),
                widget_destroy: symbol!(b"gtk_widget_destroy\0": unsafe extern "C" fn(GtkObject)),
                events_pending: symbol!(b"gtk_events_pending\0": unsafe extern "C" fn() -> i32),
                main_iteration_do: symbol!(b"gtk_main_iteration_do\0": unsafe extern "C" fn(i32) -> i32),
                object_unref: symbol!(b"g_object_unref\0": unsafe extern "C" fn(GtkObject)),
            };
            if init(ptr::null_mut(), ptr::null_mut()) == 0 {
                anyhow::bail!("Gtk could not open a display");
            }
            unsafe extern "C" fn on_delete(
                _window: GtkObject,
                _event: *mut c_void,
                closed: *mut c_void,
            ) -> i32 {
                // SAFETY: `closed` is the `*const Cell<bool>` that `wrap` passed to `g_signal_connect_data`; the Box
                // it points into is owned by the GtkWindow, which destroys the window (and so the handler)
                // before the Box drops, and Gtk calls the handler on the same thread.
                unsafe { &*(closed as *const Cell<bool>) }.set(true);
                // Handled: the host takes the window down itself.
                1
            }
            let closed = Box::new(Cell::new(false));
            let window = window_new(0);
            set_title(window, title.as_ptr());
            // Hold the widget, so taking it out of the window later does not free it.
            object_ref(widget);
            container_add(window, widget);
            connect(
                window,
                c"delete-event".as_ptr(),
                on_delete as *const c_void,
                &*closed as *const Cell<bool> as *mut c_void,
                ptr::null(),
                0,
            );
            show_all(window);
            Ok(Self {
                gtk,
                window,
                widget,
                closed,
            })
        }
    }

    /// Let Gtk handle what is waiting. Returns whether the user closed the window.
    pub(crate) fn run(&mut self) -> bool {
        // SAFETY: `gtk` holds Gtk functions found in `wrap`, and nothing here frees the window or the
        // widget, so the calls work on live objects; they run on the thread that made the window.
        unsafe {
            // Bounded, so a flood of events cannot hold the host up.
            for _ in 0..200 {
                if (self.gtk.events_pending)() == 0 {
                    break;
                }
                (self.gtk.main_iteration_do)(0);
            }
        }
        self.closed.get()
    }

    /// Take the widget out of the window, before its editor destroys it.
    pub(crate) fn release(&self) {
        // SAFETY: `window` and `widget` are live (created in `wrap`, destroyed only in Drop), and the widget
        // was added to this window, which `gtk_container_remove` requires.
        unsafe { (self.gtk.container_remove)(self.window, self.widget) };
    }
}

impl Drop for GtkWindow {
    fn drop(&mut self) {
        // SAFETY: The widget was referenced in `wrap` and the window is made there; each is released once,
        // here, and the window is destroyed after the widget reference is dropped, on the creating thread.
        unsafe {
            (self.gtk.object_unref)(self.widget);
            (self.gtk.widget_destroy)(self.window);
        }
        self.run();
    }
}

/// A top-level window for a plugin to put its editor in.
pub(crate) struct HostWindow {
    display: Rc<Display>,
    id: u32,
    size: (u32, u32),
    /// The editor cannot be resized by the user.
    fixed: bool,
}

impl HostWindow {
    pub(crate) fn new(title: &str, width: u32, height: u32) -> Result<Self> {
        tolerate_x_errors();
        let display = display()?;
        let conn = &display.conn;
        let id = conn.generate_id()?;
        let (width, height) = (width.clamp(1, 16384), height.clamp(1, 16384));
        conn.create_window(
            x11rb::COPY_DEPTH_FROM_PARENT,
            id,
            display.root,
            0,
            0,
            width as u16,
            height as u16,
            0,
            WindowClass::INPUT_OUTPUT,
            x11rb::COPY_FROM_PARENT,
            // Black where the editor does not reach, rather than whatever was
            // on screen before.
            &CreateWindowAux::new()
                .background_pixel(display.black)
                .event_mask(EventMask::STRUCTURE_NOTIFY),
        )?;
        conn.change_property8(
            PropMode::REPLACE,
            id,
            AtomEnum::WM_NAME,
            AtomEnum::STRING,
            title.as_bytes(),
        )?;
        conn.change_property8(
            PropMode::REPLACE,
            id,
            display.net_wm_name,
            display.utf8_string,
            title.as_bytes(),
        )?;
        conn.change_property8(
            PropMode::REPLACE,
            id,
            AtomEnum::WM_CLASS,
            AtomEnum::STRING,
            b"paw\0paw-plugin\0",
        )?;
        // Ask to be told when the user closes the window, instead of being killed.
        conn.change_property32(
            PropMode::REPLACE,
            id,
            display.wm_protocols,
            AtomEnum::ATOM,
            &[display.wm_delete],
        )?;
        conn.map_window(id)?;
        conn.flush()?;
        Ok(Self {
            display,
            id,
            size: (width, height),
            fixed: false,
        })
    }

    /// The X11 window id, which is what plugins take as their parent.
    pub(crate) fn id(&self) -> u32 {
        self.id
    }

    /// Say whether the editor has one size only. The window manager then
    /// offers no resizing, and a tiling one floats the window at that size
    /// instead of stretching or cropping an editor that cannot follow.
    pub(crate) fn set_fixed(&mut self, fixed: bool) {
        self.fixed = fixed;
        self.hint_size();
    }

    fn hint_size(&self) {
        let size = self
            .fixed
            .then_some((self.size.0 as i32, self.size.1 as i32));
        let hints = WmSizeHints {
            min_size: size,
            max_size: size,
            ..WmSizeHints::new()
        };
        let _ = hints.set_normal_hints(&self.display.conn, self.id);
        let _ = self.display.conn.flush();
    }

    pub(crate) fn resize(&mut self, width: u32, height: u32) {
        let (width, height) = (width.clamp(1, 16384), height.clamp(1, 16384));
        if (width, height) == self.size {
            return;
        }
        self.size = (width, height);
        self.hint_size();
        let conn = &self.display.conn;
        let _ = conn.configure_window(
            self.id,
            &ConfigureWindowAux::new().width(width).height(height),
        );
        let _ = conn.flush();
    }

    /// The size of a window inside this one: the plugin's own, once it exists.
    pub(crate) fn child_size(&self, child: u32) -> Option<(u32, u32)> {
        let geometry = self.display.conn.get_geometry(child).ok()?.reply().ok()?;
        Some((geometry.width as u32, geometry.height as u32))
    }

    /// What has happened to the window since the last call. Sizes the host
    /// set itself are not reported back.
    pub(crate) fn events(&mut self) -> Vec<WindowEvent> {
        self.display.pump();
        let mut events = self
            .display
            .events
            .borrow_mut()
            .remove(&self.id)
            .unwrap_or_default();
        events.retain(|event| match event {
            WindowEvent::Resized(w, h) if (*w, *h) == self.size => false,
            WindowEvent::Resized(w, h) => {
                self.size = (*w, *h);
                true
            }
            WindowEvent::Closed => true,
        });
        events
    }
}

impl Drop for HostWindow {
    fn drop(&mut self) {
        let _ = self.display.conn.destroy_window(self.id);
        let _ = self.display.conn.flush();
        self.display.events.borrow_mut().remove(&self.id);
    }
}

/// File descriptors and timers a plugin has asked the host to watch, each
/// tagged with whatever the format needs to call the plugin back.
pub(crate) struct Watches<F, T> {
    pub fds: Vec<(RawFd, F)>,
    timers: Vec<(Duration, Instant, T)>,
}

impl<F, T> Default for Watches<F, T> {
    fn default() -> Self {
        Self {
            fds: Vec::new(),
            timers: Vec::new(),
        }
    }
}

impl<F: Clone, T: Clone + PartialEq> Watches<F, T> {
    pub(crate) fn new() -> Self {
        Self {
            fds: Vec::new(),
            timers: Vec::new(),
        }
    }

    pub(crate) fn add_timer(&mut self, period_ms: u64, tag: T) {
        // Plugins ask for timers as fast as 1 ms; the host loop is coarser.
        let period = Duration::from_millis(period_ms.max(1));
        self.timers.push((period, Instant::now() + period, tag));
    }

    pub(crate) fn remove_timer(&mut self, tag: &T) {
        self.timers.retain(|(_, _, t)| t != tag);
    }

    /// Keep only the timers whose tag passes `keep`.
    pub(crate) fn timers_retain(&mut self, mut keep: impl FnMut(&T) -> bool) {
        self.timers.retain(|(_, _, t)| keep(t));
    }

    /// The file descriptors to call the plugin back for: all of them.
    ///
    /// Waiting for a descriptor to become readable is not enough. These are
    /// mostly X connections, and Xlib and xcb read ahead: events that arrived
    /// while the plugin waited for a reply sit in the library's own queue with
    /// nothing left on the socket, so an editor would stay blank until the
    /// next mouse movement. Plugin toolkits check their queue without
    /// blocking, so asking every time costs a function call.
    pub(crate) fn ready_fds(&self) -> Vec<(RawFd, F)> {
        self.fds.clone()
    }

    /// The timers that have come due, rescheduled for their next turn.
    pub(crate) fn due_timers(&mut self) -> Vec<T> {
        let now = Instant::now();
        let mut due = Vec::new();
        for (period, next, tag) in &mut self.timers {
            if *next <= now {
                due.push(tag.clone());
                *next = (*next + *period).max(now);
            }
        }
        due
    }
}
