//! The window: what the kernel says to draw, kept as it last said it, and
//! every frame drawn from that. A gesture is passed to the kernel's
//! `paw.frontend.act`, which says what it means; the window decides
//! nothing about the project.

use std::cell::RefCell;
use std::path::Path;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use anyhow::Result;
use egui::{Rect, Ui, pos2, vec2};
use serde_json::{Value, json};

use crate::client::Client;
use crate::model::{self, Track, flag, int, rows, text};
use crate::theme::th;
use crate::{canvas, dialogs, keys, menu, panes, portal, scene};

/// What the window asks of a kernel: calls answered, and the state pushed.
/// A client of a real kernel in the program; a stand-in in the tests.
pub trait Kernel {
    fn call(&mut self, method: &str, params: Value) -> Result<Value>;
    /// What the kernel pushed since the last time, put together; None when
    /// nothing came.
    fn state(&mut self) -> Result<Option<Value>>;
    fn send_file(&mut self, path: &Path) -> Result<String>;
    fn listening(&self) -> bool;
    /// The scenes' patches pushed since the last time (`scene.patch`).
    fn patches(&mut self) -> Vec<Value> {
        Vec::new()
    }
    /// The live values last pushed, if new (`scene.live`).
    fn live(&mut self) -> Option<Value> {
        None
    }
    /// Draw the song's moves (the playhead, the meters) `fps` times a second.
    fn set_pace(&mut self, _fps: f64) {}
}

impl Kernel for Client {
    fn call(&mut self, method: &str, params: Value) -> Result<Value> {
        Client::call(self, method, params)
    }
    fn state(&mut self) -> Result<Option<Value>> {
        Client::state(self)
    }
    fn send_file(&mut self, path: &Path) -> Result<String> {
        self.connection.send_file(path)
    }
    fn listening(&self) -> bool {
        self.player.is_some()
    }
    fn patches(&mut self) -> Vec<Value> {
        std::mem::take(&mut self.patches)
    }
    fn live(&mut self) -> Option<Value> {
        self.live.take()
    }
    fn set_pace(&mut self, fps: f64) {
        self.pace.store((1e6 / fps.max(1.0)) as u64, std::sync::atomic::Ordering::Relaxed);
        // The kernel sends what moves at the same pace, and no more often.
        let _ = self.connection.notify("frontend.pace", json!([1000.0 / fps.max(1.0)]));
    }
}

/// Taller or shorter tracks in the arrange view, by `...` rows, from the
/// height they have now.
const TRACK_HEIGHT: &str = "local by = ...; local v = paw.ui.views.arrange; \
local now = tonumber(paw.opt.track_height) or (v.geometry and v.geometry.th) or 3; \
paw.opt.track_height = paw.util.clamp(now + by, 1, 12)";

/// How long a message of the window's own stays.
const MESSAGE_TIME: Duration = Duration::from_secs(5);

/// The transport bar along the top, and the status line along the bottom.
pub const TRANSPORT_H: f32 = 40.0;
pub const STATUS_H: f32 = 22.0;

/// The frames a second the window draws while the song plays, by
/// `paw.opt.window_fps`: a number from 1 to 60, or `auto`: 30 on a
/// graphics card, 15 on the processor, where each frame costs much more.
pub fn frame_rate(option: &Value, software: bool) -> f64 {
    match option.as_f64() {
        Some(fps) => fps.clamp(1.0, 60.0),
        None if software => 15.0,
        None => 30.0,
    }
}

/// Whether the still part of the panes is kept in a texture, by
/// `paw.opt.window_cache`: true, false, or `auto`, which is on: it saves
/// processor time on a graphics card too, where the texture costs a few
/// megabytes of its memory.
pub fn cache_on(option: &Value) -> bool {
    option.as_bool().unwrap_or(true)
}

/// What the kernel last said, read.
#[derive(Default)]
pub struct State {
    /// What moves on its own: the playhead, the mode.
    pub tick: Value,
    /// The mode, the panes and what the keyboard does: shared, as each
    /// frame reads it in many places.
    pub modal: std::rc::Rc<Value>,
    pub project: Value,
    pub tracks: Vec<Track>,
    pub kinds: Vec<String>,
    pub selected: i64,
    pub revision: i64,
    pub playing: bool,
    pub recording: bool,
}

impl State {
    pub fn track(&self, id: i64) -> Option<&Track> {
        self.tracks.iter().find(|t| t.id == id)
    }
    pub fn focused(&self) -> &str {
        self.modal["focused"].as_str().unwrap_or("")
    }
}

/// What a file chosen in the desktop's dialog is for.
#[derive(Clone, Copy, Debug)]
pub enum Purpose {
    Open,
    SaveAs,
    Import,
    /// The render dialog's file field (or, for stems, the folder's name).
    Render,
}

pub struct View {
    pub k: RefCell<Box<dyn Kernel>>,
    /// Gestures to pass on at the end of the frame, as calls.
    acts: RefCell<Vec<(String, Value)>>,
    /// The kernel this window talks to is its own child: its disk is ours.
    pub ours: bool,
    pub s: State,
    pub keys: keys::Keys,
    /// Keys taken from the frame's input before egui saw them.
    pub pending_keys: Vec<egui::Event>,
    pub hooked: bool,
    /// The text boxes of the window: while one has the keyboard, keys are
    /// typed there and not sent to the kernel.
    pub text_ids: RefCell<Vec<egui::Id>>,
    pub text_focus: bool,
    /// A message of the window's own (a failed call, a drop), with when.
    pub note: Option<(String, bool, Instant)>,
    /// When the kernel's message was made, the one a key or a change of
    /// mode put away, and the mode the last state had.
    pub message_time: f64,
    pub message_dismissed: f64,
    pub last_mode: String,
    pub panes: panes::Panes,
    pub canvases: canvas::Canvases,
    pub scenes: scene::Scenes,
    pub menu: Option<menu::Menu>,
    /// The kernel's menu last shown (`modal.menu`, how many it has opened).
    pub kernel_menu: i64,
    pub dialogs: dialogs::Dialogs,
    /// The floating page the kernel draws (help, a list, a picker).
    pub float: Option<(String, Vec<String>)>,
    pub float_size: (usize, usize),
    /// The desktop's file dialogs: answers come back here.
    pub portal_answers: (mpsc::Sender<(Purpose, portal::Outcome)>, mpsc::Receiver<(Purpose, portal::Outcome)>),
    pub portal_busy: bool,
    pub portal_absent: bool,
    /// Something happened that a painted view may show.
    pub repaint: bool,
    /// The kernel's tick needs another frame soon (a peak falling, a message ending).
    pub again: Option<Duration>,
    pub gone: bool,
    pub listening: bool,
    pub ctx: Option<egui::Context>,
    /// OpenGL draws the window on the processor (llvmpipe).
    pub software: bool,
    /// The frames a second while the song plays, as last set.
    pub fps: f64,
    /// Whether a frame is drawn again only where it changed
    /// (`paw.opt.window_cache`), else whole (crate::runner).
    pub cache: bool,
    /// The window's title as last set.
    title: String,
    /// The parts of the last pass that the live values move (crate::live).
    pub live: crate::live::Parts,
}

impl View {
    pub fn new(kernel: Box<dyn Kernel>, ours: bool) -> View {
        View {
            k: RefCell::new(kernel),
            acts: RefCell::new(Vec::new()),
            ours,
            s: State { revision: -1, selected: -1, ..State::default() },
            keys: keys::Keys::default(),
            pending_keys: Vec::new(),
            hooked: false,
            text_ids: RefCell::new(Vec::new()),
            text_focus: false,
            note: None,
            message_time: 0.0,
            message_dismissed: 0.0,
            last_mode: String::new(),
            panes: panes::Panes::default(),
            canvases: canvas::Canvases::default(),
            scenes: scene::Scenes::counting(std::env::var_os("PAW_GUI_STATS").is_some()),
            menu: None,
            kernel_menu: 0,
            dialogs: dialogs::Dialogs::default(),
            float: None,
            float_size: (120, 30),
            portal_answers: mpsc::channel(),
            portal_busy: false,
            portal_absent: false,
            repaint: true,
            again: None,
            gone: false,
            listening: false,
            ctx: None,
            software: false,
            fps: 0.0,
            cache: true,
            title: String::new(),
            live: crate::live::Parts::default(),
        }
    }

    // ------------------------------------------------------------ the kernel

    /// Pass a gesture on: `paw.frontend.act.<name>(args...)`, at the end of
    /// the frame. What it means is the kernel's to say.
    pub fn pass(&self, name: &str, args: Value) {
        self.eval(&format!("return paw.frontend.act.{name}(...)"), args);
    }

    /// Run Lua in the kernel with `args` as `...`, at the end of the frame.
    pub fn eval(&self, code: &str, args: Value) {
        let mut params = vec![json!(code)];
        params.extend(args.as_array().cloned().unwrap_or_default());
        self.acts.borrow_mut().push(("eval".into(), Value::Array(params)));
    }

    /// Call a method of the kernel's, at the end of the frame.
    pub fn call_later(&self, method: &str, params: Value) {
        self.acts.borrow_mut().push((method.into(), params));
    }

    /// Run a command line, as typed after `:` in the terminal.
    pub fn command(&self, line: &str) {
        self.acts.borrow_mut().push(("cmd".into(), json!([line])));
    }

    /// Feed keys to the kernel's mappings.
    pub fn feed(&self, keys: &str) {
        self.pass("keys", json!([keys]));
    }

    /// Ask the kernel now, and have its answer: for what a frame must draw
    /// (a menu's entries, a clip's notes). A failure is shown and gives null.
    pub fn ask(&self, code: &str, args: Value) -> Value {
        let mut params = vec![json!(code)];
        params.extend(args.as_array().cloned().unwrap_or_default());
        match self.k.borrow_mut().call("eval", Value::Array(params)) {
            Ok(value) => value,
            Err(err) => {
                self.acts.borrow_mut().push(("!".into(), json!(format!("{err:#}"))));
                Value::Null
            }
        }
    }

    /// Send what was gathered in the frame.
    pub fn flush(&mut self) {
        let acts: Vec<(String, Value)> = std::mem::take(&mut *self.acts.borrow_mut());
        self.send(acts);
    }

    /// Send what was gathered in the frame before the first release of a
    /// pointer button, which stays for the end of the frame.
    pub fn flush_before_release(&mut self) {
        let early: Vec<(String, Value)> = {
            let mut acts = self.acts.borrow_mut();
            let release = acts.iter().position(|(m, p)| m == "scene.input" && p[1]["kind"] == "up").unwrap_or(acts.len());
            acts.drain(..release).collect()
        };
        self.send(early);
    }

    fn send(&mut self, acts: Vec<(String, Value)>) {
        if acts.is_empty() {
            return;
        }
        for (method, params) in acts {
            if method == "!" {
                self.show(&text(&params), true);
                continue;
            }
            let outcome = self.k.borrow_mut().call(&method, params);
            if let Err(err) = outcome {
                self.show(&format!("{err:#}"), true);
            }
        }
        self.repaint = true;
        if let Some(ctx) = &self.ctx {
            ctx.request_repaint_after(Duration::from_millis(1));
        }
    }

    /// A message of the window's own, in the toolbar.
    pub fn show(&mut self, message: &str, error: bool) {
        self.note = (!message.is_empty()).then(|| (message.to_string(), error, Instant::now()));
    }

    // ------------------------------------------------------------- the state

    /// Take in what the kernel has sent since the last frame.
    pub fn poll(&mut self) {
        let polled = self.k.borrow_mut().state();
        // The scenes' patches came in with the state.
        self.scene_patches();
        let state = match polled {
            Ok(Some(state)) => state,
            Ok(None) => return,
            Err(err) => {
                self.gone = true;
                self.show(&format!("{err:#}"), true);
                return;
            }
        };
        self.take(state);
    }

    /// Take in a state as `paw.frontend.state` gives it.
    pub fn take(&mut self, state: Value) {
        let fps = frame_rate(&state["window_fps"], self.software);
        if self.fps != fps {
            self.fps = fps;
            self.k.borrow_mut().set_pace(fps);
        }
        self.cache = cache_on(&state["window_cache"]);
        self.s.playing = flag(&state["playing"]);
        self.s.recording = flag(&state["recording"]);
        if state.get("project").is_some_and(Value::is_object) {
            self.project(&state);
        }
        self.modal(&state["modal"]);
        self.s.tick = state;
        self.repaint = true;
    }

    fn project(&mut self, state: &Value) {
        let project = &state["project"];
        self.s.revision = int(&state["revision"]);
        self.s.tracks = model::tracks(&state["tracks"]);
        if let Some(kinds) = state["kinds"].as_array() {
            self.s.kinds = kinds.iter().map(text).collect();
        }
        self.s.selected = state["selected"].as_i64().unwrap_or(-1);
        self.s.project = project.clone();
    }

    fn modal(&mut self, modal: &Value) {
        // A message stays until the next key or a change of mode, as well as
        // for the time the kernel gives it.
        let mode = text(&modal["mode"]);
        self.message_time = modal["message"]["time"].as_f64().unwrap_or(0.0);
        if mode != self.last_mode {
            self.message_dismissed = self.message_time;
            self.last_mode = mode;
        }
        self.s.modal = std::rc::Rc::new(modal.clone());
        // A floating page is drawn by the kernel as text.
        self.float = if modal["float"].is_string() {
            let page = self.ask("return paw.frontend.float(...)", json!([self.float_size.0, self.float_size.1]));
            Some((text(&page["title"]), rows(&page["lines"]).iter().map(text).collect()))
        } else {
            None
        };
        self.kernel_menu(modal);
    }

    /// The kernel's message to show, with its level (0 plain, 1 a warning,
    /// 2 an error), unless a key or a change of mode put it away.
    pub fn status_message(&self) -> Option<(String, i32)> {
        let message = &self.s.modal["message"];
        if self.message_time == self.message_dismissed || !message.is_object() {
            return None;
        }
        let level = match message["level"].as_str() {
            Some("error") => 2,
            Some("warn") => 1,
            _ => 0,
        };
        Some((text(&message["text"]), level))
    }

    // ------------------------------------------------------------- the frame

    /// Draw the window.
    pub fn frame(&mut self, ui: &mut Ui) {
        let ctx = ui.ctx().clone();
        if self.ctx.is_none() {
            self.ctx = Some(ctx.clone());
        }
        self.again = None;
        self.live.list.clear();
        self.scenes_watch(&ctx);
        self.poll();
        self.answers();
        self.listening = self.k.borrow().listening();
        if let Some((_, _, at)) = &self.note
            && at.elapsed() > MESSAGE_TIME
        {
            self.note = None;
        }
        if let Some((_, _, at)) = &self.note {
            self.again = Some(MESSAGE_TIME.saturating_sub(at.elapsed()) + Duration::from_millis(20));
        }
        // The title names the project, and says when it has changes.
        let title = format!("paw – {}{}", text(&self.s.project["name"]), if flag(&self.s.project["modified"]) { " •" } else { "" });
        if title != self.title {
            ctx.send_viewport_cmd(egui::ViewportCommand::Title(title.clone()));
            self.title = title;
        }
        self.text_ids.borrow_mut().clear();
        // The whole window, whatever margin the `ui` given has.
        let full = ctx.content_rect();
        ui.set_clip_rect(full);
        let transport = Rect::from_min_size(full.min, vec2(full.width(), TRANSPORT_H));
        let status = Rect::from_min_max(pos2(full.left(), full.bottom() - STATUS_H), full.max);
        let area = Rect::from_min_max(pos2(full.left(), transport.bottom() + 1.0), pos2(full.right(), status.top() - 1.0));
        ui.painter().hline(full.x_range(), transport.bottom() + 0.5, egui::Stroke::new(1.0, th().divider));
        ui.painter().hline(full.x_range(), status.top() - 0.5, egui::Stroke::new(1.0, th().divider));
        self.main_area(ui, area);
        self.clip_pictures(&ctx);
        self.transport(ui, transport);
        self.overlays(ui, full, status);
        self.status_line(ui, status);
        self.menu_popup(ui);
        self.dialog(ui, full);
        self.canvas_windows(&ctx);
        self.keyboard(ui);
        self.window_focus(ui);
        self.files_dropped(ui);
        self.close_requested(ui);
        self.scenes_done();
        self.flush();
        self.focus_after(&ctx);
        self.layout_keep(&ctx);
        if let Some(after) = self.again {
            ctx.request_repaint_after(after);
        }
        if self.gone && self.ours {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
    }

    /// The panes of the main area: those the window draws itself, and those
    /// the kernel paints.
    fn main_area(&mut self, ui: &mut Ui, area: Rect) {
        self.pane_area(ui, area);
        let modal = self.s.modal.clone();
        self.draw_kernel_panes(ui, area, &modal["panes"]);
    }

    /// Where keys go: to a text box of the window's while one has them, else
    /// to the kernel's mappings, the window keeping a few of its own (zoom).
    fn keyboard(&mut self, ui: &mut Ui) {
        let events: Vec<egui::Event> = if self.hooked {
            std::mem::take(&mut self.pending_keys)
        } else if self.text_focus {
            Vec::new()
        } else {
            ui.input(|i| i.events.clone())
        };
        if self.text_focus || self.dialogs.open() {
            return;
        }
        self.window_keys(&events);
    }

    /// Keys typed in a window of the program's: to the kernel's mappings,
    /// Ctrl with a few for zoom.
    pub fn window_keys(&mut self, events: &[egui::Event]) {
        let in_roll = self.s.focused() == "pianoroll";
        // Ctrl with + - 0 and the arrows zoom; the rest are the kernel's.
        let events: Vec<egui::Event> = events
            .iter()
            .filter(|event| match event {
                egui::Event::Key { key, pressed: true, modifiers, .. } if modifiers.ctrl && !modifiers.alt => !self.window_key(*key),
                _ => true,
            })
            .cloned()
            .collect();
        for keys in self.keys.notations(&events) {
            let keys = keys::window_keys(keys, in_roll);
            self.message_dismissed = self.message_time;
            // A key closes a menu that was open, as a click elsewhere does.
            self.let_go_menu();
            self.acts.borrow_mut().push(("keys".into(), json!([keys])));
        }
    }

    /// Zoom: Ctrl with + and - in time (the focused view's, as `zi` and
    /// `zo` do), with 0 for the whole song, with the up and down keys for
    /// the height of the tracks.
    fn window_key(&mut self, key: egui::Key) -> bool {
        match key {
            egui::Key::Plus | egui::Key::Equals => self.command("zoom by=1.4142"),
            egui::Key::Minus => self.command("zoom by=0.7071"),
            egui::Key::Num0 => self.command("zoom fit"),
            egui::Key::ArrowUp => self.eval(TRACK_HEIGHT, json!([-1])),
            egui::Key::ArrowDown => self.eval(TRACK_HEIGHT, json!([1])),
            _ => return false,
        }
        true
    }

    /// Keep keyboard focus off anything but a text box of the window's, so
    /// that no button is pressed by Space or Enter and Tab moves nothing.
    fn focus_after(&mut self, ctx: &egui::Context) {
        let ids = self.text_ids.borrow();
        let focused = ctx.memory(|m| m.focused());
        if let Some(id) = focused
            && !ids.contains(&id)
        {
            ctx.memory_mut(|m| m.surrender_focus(id));
        }
        self.text_focus = focused.is_some_and(|id| ids.contains(&id));
    }

    // ------------------------------------------------------- leaving, files

    /// Leaving the project (quitting, a new one, opening another) asks first
    /// when there are changes to save. Returns whether it asked.
    pub fn leave(&mut self, what: &str) -> bool {
        let closing = self.ask("return paw.frontend.closing()", json!([]));
        // A kernel that was running before this window is not this
        // window's to save or to end.
        if flag(&closing["modified"]) && (self.ours || what != "quit") {
            self.dialogs.closing = Some((text(&closing["name"]), what.to_string()));
            return true;
        }
        if what == "quit" {
            if let Some(ctx) = &self.ctx {
                ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            }
            self.dialogs.quitting = true;
        } else {
            self.pass("leave", json!(["go", what]));
        }
        false
    }

    /// The answer to the question about unsaved changes: "save",
    /// "discard" or "cancel".
    pub fn close_choice(&mut self, choice: &str) {
        let Some((_, what)) = self.dialogs.closing.take() else { return };
        if choice != "cancel" {
            // Saved or not, the kernel then does what was asked: when that
            // was to quit, the window goes when the kernel has.
            self.pass("leave", json!([choice, what]));
        }
    }

    /// What an entry a menu leaves to the window does.
    pub fn window_action(&mut self, what: &str) {
        match what {
            "new" | "quit" => {
                self.leave(what);
            }
            "open" => {
                if !self.native(Purpose::Open, "", false) {
                    self.leave("open");
                }
            }
            "saveas" => {
                if !self.native(Purpose::SaveAs, "", false) {
                    self.command("saveas");
                }
            }
            "import" => {
                if !self.native(Purpose::Import, "", false) {
                    self.command("import");
                }
            }
            "render" => self.open_render(),
            "listen" => self.command("listen"),
            other if other.starts_with("open:") => {
                self.leave(other);
            }
            _ => {}
        }
    }

    /// The desktop's own file dialog, where the kernel is this window's own
    /// child (its disk is ours) and `paw.opt.native_dialogs` is on. It runs
    /// on a thread, so that the window goes on; the answer comes back to
    /// `answers`. Returns whether a dialog is being shown.
    pub fn native(&mut self, purpose: Purpose, render_path: &str, stems: bool) -> bool {
        // A sound file to import can come from this machine whatever the
        // kernel's is: it is sent there.
        let here = self.ours || matches!(purpose, Purpose::Import);
        if !here || self.portal_absent {
            return false;
        }
        if self.portal_busy {
            return true;
        }
        let info = self.ask("return paw.frontend.dialog_info()", json!([]));
        if !flag(&info["native"]) {
            return false;
        }
        let ask = dialogs::portal_ask(purpose, &info, render_path, stems);
        self.portal_busy = true;
        let (sender, ctx) = (self.portal_answers.0.clone(), self.ctx.clone());
        std::thread::spawn(move || {
            let outcome = portal::choose(&ask);
            let _ = sender.send((purpose, outcome));
            if let Some(ctx) = ctx {
                ctx.request_repaint();
            }
        });
        true
    }

    /// What the desktop's dialogs answered.
    fn answers(&mut self) {
        while let Ok((purpose, outcome)) = self.portal_answers.1.try_recv() {
            self.portal_busy = false;
            match outcome {
                portal::Outcome::Cancelled => {}
                portal::Outcome::Unavailable => {
                    self.portal_absent = true;
                    match purpose {
                        Purpose::Open => {
                            self.leave("open");
                        }
                        Purpose::SaveAs => self.command("saveas"),
                        Purpose::Import => self.command("import"),
                        Purpose::Render => {}
                    }
                }
                portal::Outcome::Chosen(path) => {
                    let path = path.to_string_lossy().to_string();
                    match purpose {
                        Purpose::Open => {
                            self.leave(&format!("open:{path}"));
                        }
                        Purpose::SaveAs => self.pass("chosen", json!(["saveas", path])),
                        // Chosen here for a kernel elsewhere: sent there first.
                        Purpose::Import if !self.ours => {
                            let sent = self.k.borrow_mut().send_file(Path::new(&path));
                            match sent {
                                Ok(there) => self.pass("chosen", json!(["import", there])),
                                Err(err) => self.show(&format!("{err:#}"), true),
                            }
                        }
                        Purpose::Import => self.pass("chosen", json!(["import", path])),
                        Purpose::Render => self.dialogs.render_path_chosen(path),
                    }
                }
            }
        }
    }

    /// The window got the focus of the desktop, or lost it: the kernel acts
    /// then on changes made to the project's files meanwhile.
    fn window_focus(&mut self, ui: &Ui) {
        let changes: Vec<bool> = ui.input(|i| {
            i.events
                .iter()
                .filter_map(|e| match e {
                    egui::Event::WindowFocused(on) => Some(*on),
                    _ => None,
                })
                .collect()
        });
        for on in changes {
            self.eval("paw.frontend.act.focus(...)", json!([on]));
        }
    }

    /// Files dragged in from a file manager (X11): the kernel puts each sound
    /// file on a track of its own, a MIDI file's tracks at the cursor, and
    /// asks about a project. A kernel this window attached to is sent the
    /// sound and MIDI files first.
    fn files_dropped(&mut self, ui: &Ui) {
        let (hovered, dropped) = ui.input(|i| (!i.raw.hovered_files.is_empty(), i.raw.dropped_files.clone()));
        if hovered && self.note.as_ref().is_none_or(|n| !n.0.starts_with("Drop")) {
            let message = if self.ours { "Drop to add the files to the project" } else { "Drop to send the sound and MIDI files to the instance and add them" };
            self.show(message, false);
        }
        let mut paths: Vec<String> = dropped.iter().map(|f| f.path().to_string_lossy().to_string()).filter(|p| !p.is_empty()).collect();
        if paths.is_empty() {
            return;
        }
        self.note = None;
        if !self.ours {
            let mut there = Vec::new();
            for path in &paths {
                let sound = self.ask(
                    "local path = ...; return paw.is_audio_file(path) or paw.midifile.is_midi_file(path)",
                    json!([path]),
                );
                if sound.as_bool() != Some(true) {
                    let name = Path::new(path).file_name().map_or(path.clone(), |n| n.to_string_lossy().into_owned());
                    self.eval("paw.notify(..., 'warn')", json!([format!("cannot send {name}: only sound and MIDI files go to an instance on another machine")]));
                    continue;
                }
                let sent = self.k.borrow_mut().send_file(Path::new(path));
                match sent {
                    Ok(path) => there.push(path),
                    Err(err) => {
                        self.show(&format!("{err:#}"), true);
                        return;
                    }
                }
            }
            paths = there;
        }
        let done = self.ask("return paw.frontend.act.drop(...)", json!([paths]));
        if let Some(project) = done["open"].as_str() {
            self.leave(&format!("open:{project}"));
        }
    }

    /// Closing the window asks about unsaved changes first, as quitting does.
    fn close_requested(&mut self, ui: &Ui) {
        if !ui.input(|i| i.viewport().close_requested()) {
            return;
        }
        self.layout_save(ui.ctx());
        if self.dialogs.quitting || self.gone {
            return;
        }
        if self.leave("quit") {
            ui.ctx().send_viewport_cmd(egui::ViewportCommand::CancelClose);
        }
    }

    // ------------------------------------------------------------- layout

    /// How the window is now, for the kernel to keep: its size and place
    /// (X11 tells a program where its window is; Wayland does not). What
    /// its panes show is the kernel's layout, which the project keeps.
    pub fn layout(&self, ctx: &egui::Context) -> Value {
        let (size, at) = ctx.input(|i| (i.viewport().inner_rect.map(|r| r.size()), i.viewport().outer_rect.map(|r| r.min)));
        let ppp = ctx.pixels_per_point();
        let size = size.unwrap_or(vec2(1400.0, 860.0));
        let mut layout = json!({ "width": size.x.round(), "height": size.y.round() });
        if let Some(at) = at
            && std::env::var_os("WAYLAND_DISPLAY").is_none()
        {
            layout["x"] = json!((at.x * ppp).round());
            layout["y"] = json!((at.y * ppp).round());
        }
        layout
    }

    fn layout_save(&mut self, ctx: &egui::Context) {
        let layout = self.layout(ctx);
        let _ = self.k.borrow_mut().call("eval", json!(["paw.frontend.layout_set(...)", layout]));
    }

    /// Keep the layout once a change has stood for a second.
    fn layout_keep(&mut self, ctx: &egui::Context) {
        let now = self.layout(ctx);
        let keep = &mut self.dialogs.layout;
        if keep.seen.as_ref() != Some(&now) {
            keep.seen = Some(now);
            keep.since = Instant::now();
            self.again = Some(self.again.map_or(Duration::from_millis(1100), |a| a.min(Duration::from_millis(1100))));
        } else if keep.seen != keep.done && keep.since.elapsed() >= Duration::from_secs(1) {
            keep.done = keep.seen.clone();
            let layout = keep.done.clone().unwrap_or_default();
            self.eval("paw.frontend.layout_set(...)", json!([layout]));
            self.flush();
        } else if keep.seen != keep.done {
            self.again = Some(Duration::from_millis(250));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::rc::Rc;

    /// A kernel that keeps the pace it is set to.
    struct Paced(Rc<RefCell<Vec<f64>>>);

    impl Kernel for Paced {
        fn call(&mut self, _method: &str, _params: Value) -> Result<Value> {
            Ok(Value::Null)
        }
        fn state(&mut self) -> Result<Option<Value>> {
            Ok(None)
        }
        fn send_file(&mut self, path: &Path) -> Result<String> {
            Ok(path.to_string_lossy().into())
        }
        fn listening(&self) -> bool {
            false
        }
        fn set_pace(&mut self, fps: f64) {
            self.0.borrow_mut().push(fps);
        }
    }

    #[test]
    fn the_song_is_drawn_at_the_pace_of_window_fps_slower_on_the_processor() {
        assert_eq!(frame_rate(&json!("auto"), false), 30.0);
        assert_eq!(frame_rate(&json!("auto"), true), 15.0);
        assert_eq!(frame_rate(&Value::Null, true), 15.0, "a kernel without the option");
        assert_eq!(frame_rate(&json!(10), true), 10.0);
        assert_eq!(frame_rate(&json!(500), false), 60.0);
        assert!(cache_on(&json!("auto")) && cache_on(&json!(true)) && !cache_on(&json!(false)));
        let paces = Rc::new(RefCell::new(Vec::new()));
        let mut view = View::new(Box::new(Paced(paces.clone())), true);
        view.software = true;
        view.take(json!({ "window_fps": "auto" }));
        view.take(json!({ "window_fps": "auto" }));
        assert_eq!(*paces.borrow(), vec![15.0], "set once, when it changes");
        view.take(json!({ "window_fps": 24 }));
        assert_eq!(*paces.borrow(), vec![15.0, 24.0]);
    }
}
