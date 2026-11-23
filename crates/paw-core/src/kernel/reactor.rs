//! The reactor: one turn of the kernel's loop, and the one wait between
//! turns. `Kernel::run`, `paw.api.step` and `paw.api.wait` (on both clocks)
//! turn the loop only through [`Reactor::turn`], and a request of a
//! connection closes its turn through [`Reactor::close_turn`]. The order of
//! a turn is in `docs/reference/the-order-of-a-turn.md`.
//!
//! A turn:
//!
//! 1. Messages: the input of the terminals, the requests and closes of
//!    connections, then the MIDI that came in and the output of helpers.
//! 2. Upkeep: the session looks after the engine, the plugins, the bakes,
//!    the renders and the watched files (`Session::idle`). The stepped
//!    engine first plays its blocks up to the time of the turn.
//! 3. Timers: the Lua timers due at the time of the turn, in due order.
//! 4. Close: push the edits to the engine (the sync), run the jobs of
//!    extensions (none yet), deliver the events, run the edit hooks, send
//!    the scenes and the state, and close the undo step.
//! 5. Agenda: what is ready now, what is in flight, and when the next
//!    timer or delay is due.

use std::collections::HashMap;
use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use mlua::{FromLuaMulti, Function, IntoLuaMulti, Lua, LuaSerdeExt, Table, Value as LuaValue};
use serde_json::Value;

use super::{Frontend, InputEvent, KernelMsg, told};
use crate::api::{self, Shared};
use crate::clock::{Agenda, ScheduleTime};
use crate::grid::{Caps, Color, Grid, Style};
use crate::remote::{self, RemoteFrontend};
use crate::rpc::ClientId;

/// How long the loop sleeps at most while the session needs looking after
/// (`Session::needs_idle`: a plugin, a load, a render, a watched device)
/// or work is in flight on other threads: plugin editors draw in the
/// upkeep, so this is also their frame rate.
const IDLE_PERIOD: Duration = Duration::from_millis(16);

/// The turns at one instant of the manual clock before it moves on. A job
/// that looks again at no delay (`paw.defer(fn, 0)`) for a state that a
/// later timer makes is due at each turn: without this limit the clock
/// never gets to that timer.
const TURNS_AT_ONE_INSTANT: u32 = 1000;

/// The most schedule time between two turns while the engine is stepped
/// (about ten blocks): what it played is heard of, and a take is written,
/// before it plays more.
const AUDIO_TURN: Duration = Duration::from_millis(100);

/// The most wall time that the manual clock waits for the writers of the
/// takes that closed. A writer ends in milliseconds; a disk that hangs
/// does not stop the clock for ever.
const MOST_TAKE_WAIT: Duration = Duration::from_secs(30);

/// The request that first ends the turn of the terminal keys before it
/// (`frontend.sync`).
const SYNC_METHOD: &str = "frontend.sync";

/// The next message, if one comes within `wait`.
#[cfg(not(target_vendor = "browserpod"))]
fn recv_timeout<T>(rx: &Receiver<T>, wait: Duration) -> Result<T, RecvTimeoutError> {
    rx.recv_timeout(wait)
}

/// The next message, if one comes within `wait`. In a BrowserPod pod a
/// wait with a timeout does not end at its time, only when a message comes,
/// so the timers would fire only after a key. A short sleep does end: the
/// loop asks the channel again after each one.
#[cfg(target_vendor = "browserpod")]
#[expect(clippy::disallowed_methods, reason = "a wait on the wall clock in a pod, where a timeout does not end")]
fn recv_timeout<T>(rx: &Receiver<T>, wait: Duration) -> Result<T, RecvTimeoutError> {
    use std::sync::mpsc::TryRecvError;
    const STEP: Duration = Duration::from_millis(5);
    let end = std::time::Instant::now() + wait;
    loop {
        match rx.try_recv() {
            Ok(msg) => return Ok(msg),
            Err(TryRecvError::Disconnected) => return Err(RecvTimeoutError::Disconnected),
            Err(TryRecvError::Empty) => {}
        }
        let left = end.saturating_duration_since(std::time::Instant::now());
        if left.is_zero() {
            return Err(RecvTimeoutError::Timeout);
        }
        std::thread::sleep(left.min(STEP));
    }
}

/// What the kernel keeps for the terminals that show the screen and for
/// the connections: a turn reaches it also when a script turns the loop.
pub(crate) struct Desk {
    /// Everything showing the grid: the program's own terminal (as
    /// connection 0) and the terminals attached over connections, each
    /// drawn from its own seat at its own size.
    pub(super) frontends: Vec<(ClientId, Box<dyn Frontend>)>,
    /// Files being sent over connections (`file.*`).
    uploads: crate::upload::Uploads,
    /// What is played, sent to connections that listen (`monitor.*`).
    monitor: crate::monitor::Monitor,
    /// The frame each terminal was shown last, by connection (0 for the
    /// program's own), for drawing only its live parts again.
    kept: HashMap<ClientId, Kept>,
}

impl Desk {
    pub(super) fn new(clients: crate::rpc::Clients) -> Self {
        Self {
            frontends: Vec::new(),
            uploads: Default::default(),
            monitor: crate::monitor::Monitor::new(clients),
            kept: HashMap::new(),
        }
    }
}

/// A terminal's last frame and where its cursor was.
#[derive(Default)]
struct Kept {
    grid: Grid,
    cursor: Option<(u16, u16)>,
}

/// The kernel's state and its Lua state, lent for a piece of work: what
/// the loop of the program and a Lua callback that turns the loop
/// (`paw.api.step`) both have.
pub(crate) struct Reactor<'a> {
    shared: &'a Shared,
    lua: &'a Lua,
}

impl<'a> Reactor<'a> {
    pub(crate) fn new(shared: &'a Shared, lua: &'a Lua) -> Self {
        Self { shared, lua }
    }

    /// One turn of the loop at `now` (see the order at the top of this
    /// module). Gives what is left to do after it.
    pub(crate) fn turn(&self, now: ScheduleTime) -> Agenda {
        // A turn inside a turn (a handler that waits) keeps the input and
        // the requests for the turn around it.
        let nested = self.shared.turning.replace(true);
        self.begin(now);
        self.take_messages(nested);
        self.shared.session.borrow_mut().idle();
        self.fire_timers(now);
        self.close_turn();
        // What is played goes to the connections that listen.
        let mut session = self.shared.session.borrow_mut();
        self.shared.desk.borrow_mut().monitor.keep_fed(&mut session);
        drop(session);
        self.shared.turning.set(nested);
        self.agenda(now)
    }

    /// Give the session the time of the turn: each "when" in it reads it.
    pub(crate) fn begin(&self, now: ScheduleTime) {
        self.shared.session.borrow_mut().set_now(now);
    }

    /// Step 1: the messages taken from the channel, in the order they
    /// came. In a nested turn only MIDI and helper output are heard: the
    /// input and the requests wait for the outer turn.
    fn take_messages(&self, nested: bool) {
        {
            let mut inbox = self.shared.inbox.borrow_mut();
            inbox.extend(self.shared.rx.try_iter());
            if nested {
                inbox.retain(|msg| !matches!(msg, KernelMsg::Midi | KernelMsg::Output));
            }
        }
        if !nested {
            // Not held while a message is handled: a handler may turn the
            // loop again.
            while let Some(msg) = self.shared.inbox.borrow_mut().pop_front() {
                self.handle(msg);
            }
        }
        // `Midi` and `Output` only wake the loop: what came waits in
        // queues of its own.
        self.shared.hear_midi();
        self.shared.hear_output();
    }

    /// Step 3: the Lua timers due at `now`.
    fn fire_timers(&self, now: ScheduleTime) {
        for key in api::due_timers(self.shared, now) {
            let func = self.lua.registry_value::<Function>(&key);
            if let Err(err) = func.and_then(|func| self.call::<()>("timer", func)) {
                self.report("timer", err);
            }
        }
    }

    /// Step 4: finish a turn. Push the edits to the engine, deliver the
    /// events they caused, run the edit hooks, send the scenes, and close
    /// the undo step.
    pub(crate) fn close_turn(&self) {
        // a. The sync: the engine gets the edits, automation is written,
        // files are read ahead, the media is looked after.
        self.shared.session.borrow_mut().push_edits();
        // b. The jobs of extensions that the sync collects run here, with
        // no borrow of the session: none yet.
        // c to e. In Lua: deliver the events, the edit hooks, the scenes
        // and the state of the connections.
        if let Err(err) = self.call::<()>("close_turn", ()) {
            self.report("close_turn", err);
        }
        // f. The undo step.
        self.shared.session.borrow_mut().checkpoint();
    }

    /// Step 5: what is ready at `now`, what is in flight, and the first
    /// time after `now` when a timer or a delay is due.
    pub(crate) fn agenda(&self, now: ScheduleTime) -> Agenda {
        let timers = {
            let timers = self.shared.timers.borrow();
            Agenda {
                ready: timers.iter().any(|t| t.due <= now),
                in_flight: 0,
                next_due: timers.iter().map(|t| t.due).filter(|&due| due > now).min(),
            }
        };
        let messages = Agenda {
            ready: !self.shared.inbox.borrow().is_empty() || !self.shared.midi_in.lock().unwrap().is_empty(),
            ..Agenda::default()
        };
        let work = self.shared.session.borrow().work();
        let session = Agenda {
            ready: work.next_due.is_some_and(|due| due <= now),
            in_flight: u32::try_from(work.bakes_running + work.hashing + work.plugin_loads + work.renders)
                .unwrap_or(u32::MAX),
            next_due: work.next_due.filter(|&due| due > now),
        };
        timers | messages | session
    }

    /// The longest the loop may sleep at `now` before its next turn: until
    /// the next due time, and at most [`IDLE_PERIOD`] while the session
    /// needs looking after or work is in flight. None: until a message.
    fn sleep_for(&self, agenda: &Agenda, now: ScheduleTime) -> Option<Duration> {
        if agenda.ready {
            return Some(Duration::ZERO);
        }
        let due = agenda.next_due.map(|due| due - now);
        let looked_after = self.shared.session.borrow().needs_idle() || agenda.in_flight > 0;
        let tick = looked_after.then_some(IDLE_PERIOD);
        due.into_iter().chain(tick).min()
    }

    /// The one wait of the loop: sleep until a message comes or `limit`
    /// passes (None: until a message), as the agenda allows. A message
    /// that comes waits in the inbox for the next turn.
    pub(crate) fn wait(&self, agenda: &Agenda, now: ScheduleTime, limit: Option<Duration>) -> Result<()> {
        let timeout = self.sleep_for(agenda, now).into_iter().chain(limit).min();
        let msg = match timeout {
            Some(timeout) => match recv_timeout(&self.shared.rx, timeout) {
                Ok(msg) => msg,
                Err(RecvTimeoutError::Timeout) => return Ok(()),
                Err(RecvTimeoutError::Disconnected) => return Err(anyhow!("kernel channel closed")),
            },
            None => self.shared.rx.recv()?,
        };
        self.shared.inbox.borrow_mut().push_back(msg);
        Ok(())
    }

    /// Let `by` of schedule time pass (`paw.api.wait`), with turns as the
    /// clock moves.
    pub(crate) fn wait_for(&self, by: Duration) -> Result<()> {
        if self.shared.clock.is_manual() {
            self.advance(by);
            Ok(())
        } else {
            self.wait_on_the_wall(by)
        }
    }

    /// Let `by` of schedule time pass on the manual clock: move the clock
    /// from one due time to the next, with a turn at each, so that each
    /// timer fires in its order and sees its own time. A stepped engine
    /// plays the blocks of that time in the turns.
    pub(crate) fn advance(&self, by: Duration) {
        let clock = &self.shared.clock;
        let target = clock.now() + by;
        let mut turns_here = 0;
        loop {
            let now = clock.now();
            let mut agenda = self.turn(now);
            if self.shared.session.borrow().takes_writing() > 0 {
                agenda = self.wait_for_take_writers(now);
            }
            // A turn can start a timer that is due at once (`paw.defer`).
            turns_here += 1;
            let timers_due = self.shared.timers.borrow().iter().any(|t| t.due <= now);
            if turns_here < TURNS_AT_ONE_INSTANT && timers_due {
                continue;
            }
            turns_here = 0;
            let mut next = agenda.next_due;
            if self.shared.session.borrow().is_audio_stepped() {
                let audio = now + AUDIO_TURN;
                next = Some(next.map_or(audio, |due| due.min(audio)));
            }
            match next {
                Some(due) if due <= target => self.move_clock(due),
                _ => break,
            }
        }
        self.move_clock(target);
        let _ = self.turn(clock.now());
    }

    /// Wait on the wall clock while the writers of a take that closed
    /// write its files, with a turn each millisecond at the same `now`:
    /// the take becomes clips before the manual clock moves on, so that a
    /// wait in song time for those clips (the doctor's recording) sees
    /// them. Gives the agenda of the last turn.
    #[expect(clippy::disallowed_methods, reason = "a budget of wall time for the writer threads of a take")]
    fn wait_for_take_writers(&self, now: ScheduleTime) -> Agenda {
        let deadline = std::time::Instant::now() + MOST_TAKE_WAIT;
        let mut agenda = self.agenda(now);
        while self.shared.session.borrow().takes_writing() > 0 && std::time::Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(1));
            agenda = self.turn(now);
        }
        agenda
    }

    fn move_clock(&self, to: ScheduleTime) {
        // Only `advance` moves the clock, and only on the manual clock.
        let moved = self.shared.clock.advance_to(to);
        debug_assert!(moved.is_ok(), "the manual clock moves");
    }

    /// Let `by` of wall time pass, with a turn at each message and each
    /// due time, as the loop of the program does.
    fn wait_on_the_wall(&self, by: Duration) -> Result<()> {
        let clock = &self.shared.clock;
        let deadline = clock.now() + by;
        loop {
            let now = clock.now();
            let agenda = self.turn(now);
            if now >= deadline {
                return Ok(());
            }
            self.wait(&agenda, now, Some(deadline - now))?;
        }
    }

    /// Call one of the entry points the Lua runtime registers in `paw._kernel`.
    pub(crate) fn call<R: FromLuaMulti>(&self, name: &str, args: impl IntoLuaMulti) -> mlua::Result<R> {
        let paw: Table = self.lua.globals().get("paw")?;
        let kernel: Table = paw.get("_kernel")?;
        kernel.get::<Function>(name)?.call(args)
    }

    pub(crate) fn report(&self, what: &str, err: mlua::Error) {
        let line = format!("{what}: {err}");
        if !self.shared.attached.get() {
            eprintln!("{line}");
        }
        self.shared.log(line);
    }

    /// Make it `client`'s turn: what happens next happens in its seat (the
    /// instance's when it has none of its own).
    pub(crate) fn enter(&self, client: ClientId) {
        self.shared.seat.set(client);
        if let Err(err) = self.call::<()>("seat", client) {
            self.report("seat", err);
        }
    }

    /// A terminal's keys, pointer and size, in its own seat.
    fn input(&self, client: ClientId, event: InputEvent) {
        self.enter(client);
        // A key asks for its own frame (`K.key` in paw/init.lua): the whole
        // screen, or only the lines when it only waits for the next key.
        let key = matches!(event, InputEvent::Key(_));
        let result = match event {
            InputEvent::Key(key) => self.call::<()>("key", key),
            InputEvent::Paste(text) => self.call::<()>("paste", text),
            InputEvent::Mouse {
                kind,
                button,
                x,
                y,
                mods,
                pixel,
            } => (|| {
                let event = self.lua.create_table()?;
                event.set("kind", kind)?;
                event.set("button", button)?;
                event.set("x", x)?;
                event.set("y", y)?;
                event.set("mods", mods)?;
                if let Some((px, py)) = pixel {
                    event.set("px", px)?;
                    event.set("py", py)?;
                }
                self.call::<()>("mouse", event)
            })(),
            InputEvent::Resize(width, height) => {
                self.shared.sizes.borrow_mut().insert(client, (width, height));
                self.shared.grid.borrow_mut().resize(width, height);
                self.call::<()>("resize", (width, height))
            }
            InputEvent::CellSize(width, height) => {
                if let Some(caps) = self.shared.caps.borrow_mut().get_mut(&client) {
                    caps.cell = (width, height);
                }
                Ok(())
            }
            InputEvent::Focus(on) => self.call::<()>("focus", on),
        };
        // A key whose Lua failed asked for nothing: the whole screen then.
        if !key || result.is_err() {
            self.shared.dirty.set(true);
        }
        if let Err(err) = result {
            self.report("input", err);
        }
    }

    /// The calls that are the kernel's own business rather than Lua's: a
    /// connection becoming a terminal, typing into it, and leaving.
    fn remote_ui(&self, client: ClientId, method: &str, params: &Value) -> Result<Value> {
        match method {
            "ui.attach" => {
                let size = |v: &Value, default| v.as_u64().map_or(default, |n| n.clamp(1, 1000) as u16);
                let (width, height) = (size(&params[0], 80), size(&params[1], 24));
                let frontend = RemoteFrontend::new(client, self.shared.clients.clone());
                {
                    let mut desk = self.shared.desk.borrow_mut();
                    desk.frontends.retain(|(id, _)| *id != client);
                    desk.frontends.push((client, Box::new(frontend)));
                }
                // What its terminal can show: without a word, cells only.
                self.shared.caps.borrow_mut().insert(client, Caps::from_json(&params[2]));
                self.shared.attached.set(true);
                // A seat of its own: its own cursor, mode and selection.
                if let Err(err) = self.call::<()>("seat_open", (client, "terminal")) {
                    self.report("seat_open", err);
                }
                self.input(client, InputEvent::Resize(width, height));
                Ok(Value::Bool(true))
            }
            "ui.input" => {
                if !self.shared.desk.borrow().frontends.iter().any(|(id, _)| *id == client) {
                    bail!("`ui.attach` first");
                }
                let event = remote::input_of(&params[0]).context("not an input event")?;
                // Lua may ask which terminal a key came from (`:detach`).
                self.shared.input_from.set(client);
                self.input(client, event);
                self.shared.input_from.set(0);
                Ok(Value::Null)
            }
            "ui.detach" => {
                self.detach(client);
                Ok(Value::Bool(true))
            }
            _ => bail!("no method `{method}`"),
        }
    }

    /// Stop showing the screen to a connection.
    fn detach(&self, client: ClientId) {
        let (removed, empty) = {
            let mut desk = self.shared.desk.borrow_mut();
            let before = desk.frontends.len();
            desk.frontends.retain(|(id, _)| *id != client);
            desk.kept.remove(&client);
            (desk.frontends.len() != before, desk.frontends.is_empty())
        };
        if removed {
            self.shared.clients.push(client, "ui.detached", &Value::Null);
            self.shared.sizes.borrow_mut().remove(&client);
            self.shared.caps.borrow_mut().remove(&client);
            self.enter(0);
            if let Err(err) = self.call::<()>("seat_close", (client, "terminal")) {
                self.report("seat_close", err);
            }
        }
        if empty {
            self.shared.attached.set(false);
        }
    }

    /// A request of a connection to the Lua runtime (`eval`, `cmd`, the
    /// methods of paw/remote.tl), in the seat of `client`. It is one action,
    /// so it is a turn of its own: the turn closes before the answer goes.
    fn request(&self, client: ClientId, method: String, params: &Value) -> Result<Value> {
        // The barrier of a frontend (paw/remote.tl): the terminal keys taken
        // before it in this turn end their turn first. Their events go out,
        // their undo step closes, and what they changed is pushed before the
        // answer.
        if method == SYNC_METHOD {
            self.close_turn();
        }
        self.enter(client);
        // A command run over a connection may answer it (`:upload`, `:listen`).
        self.shared.input_from.set(client);
        let result = (|| {
            let params = api::to_lua(self.lua, params)?;
            let value: LuaValue = self.call("rpc", (method, params, client))?;
            self.lua.from_value::<Value>(value)
        })()
        .map_err(|err| anyhow!(told(&err)));
        self.shared.input_from.set(0);
        // The end of the turn, in the instance's seat as at the end of each
        // turn of `run`. A client that sends its next request at once gets
        // it in the same batch of messages, so without this its requests
        // shared one turn: one undo step, and no events until it paused.
        // The events are queued before the answer, so the client reads them
        // first.
        self.enter(0);
        self.close_turn();
        result
    }

    fn handle(&self, msg: KernelMsg) {
        match msg {
            KernelMsg::Input(event) => self.input(0, event),
            // What came waits in queues of its own: the end of step 1
            // hears it.
            KernelMsg::Midi | KernelMsg::Output => {}
            KernelMsg::Rpc {
                client,
                method,
                params,
                reply,
            } => {
                let result = if method.starts_with("ui.") {
                    self.remote_ui(client, &method, &params)
                } else if method.starts_with("file.") {
                    let dir = self.shared.session.borrow().media_dir();
                    self.shared.desk.borrow_mut().uploads.call(client, &method, &params, &dir)
                } else if method.starts_with("monitor.") {
                    let mut session = self.shared.session.borrow_mut();
                    self.shared.desk.borrow_mut().monitor.call(client, &method, &mut session)
                } else {
                    self.request(client, method, &params)
                };
                // The one place an error becomes the text a client sees.
                let _ = reply.send(result.map_err(|err| format!("{err:#}")));
            }
            KernelMsg::Gone(client) => {
                self.detach(client);
                {
                    let mut desk = self.shared.desk.borrow_mut();
                    desk.uploads.closed(client);
                    desk.monitor.closed(client, &mut self.shared.session.borrow_mut());
                }
                if let Err(err) = self.call::<()>("rpc_closed", client) {
                    self.report("rpc_closed", err);
                }
            }
        }
        self.enter(0);
        // A terminal that asked to leave (`:detach`) is let go.
        let leaving: Vec<ClientId> = self.shared.detach.borrow_mut().drain(..).collect();
        for client in leaving {
            self.detach(client);
        }
    }

    /// Draw the screen on each terminal that shows it: only the live parts,
    /// unless something else asked for a frame.
    pub(crate) fn render(&self) {
        let live_only = !self.shared.dirty.get();
        self.shared.dirty.set(false);
        self.shared.live_dirty.set(false);
        let clients: Vec<ClientId> = self.shared.desk.borrow().frontends.iter().map(|(id, _)| *id).collect();
        if clients.is_empty() {
            return;
        }
        let mut gone = Vec::new();
        for client in clients {
            // Each terminal keeps the frame it was shown last, and is drawn
            // from its own seat, at its own size.
            let (width, height) = self.shared.sizes.borrow().get(&client).copied().unwrap_or_else(|| {
                let grid = self.shared.grid.borrow();
                (grid.width, grid.height)
            });
            let kept = self.shared.desk.borrow_mut().kept.remove(&client);
            let mut kept = kept.unwrap_or_else(|| Kept { grid: Grid::new(width, height), cursor: None });
            if (kept.grid.width, kept.grid.height) != (width, height) {
                kept.grid.resize(width, height);
            }
            std::mem::swap(&mut *self.shared.grid.borrow_mut(), &mut kept.grid);
            self.enter(client);
            let mut changed = true;
            let mut drawn_live = false;
            let can_live = {
                let grid = self.shared.grid.borrow();
                live_only && !grid.live.is_empty() && grid.surfaces.is_empty()
            };
            if can_live {
                self.shared.cursor.set(kept.cursor);
                match api::render_live(self.lua, self.shared) {
                    Ok(done) => drawn_live = done,
                    Err(err) => self.report("render_live", err),
                }
                if drawn_live {
                    changed = self.shared.grid.borrow().live_changed();
                }
            }
            let mut frames = self.shared.frames.get();
            if drawn_live {
                frames[if changed { 1 } else { 2 }] += 1;
            } else {
                frames[0] += 1;
                self.shared.grid.borrow_mut().clear();
                self.shared.cursor.set(None);
                let result = api::render(self.lua, self.shared);
                if let Err(err) = result {
                    // The Lua UI is broken, so the kernel draws the reason itself.
                    let mut grid = self.shared.grid.borrow_mut();
                    grid.live.clear();
                    let style = Style {
                        fg: Some(Color::Indexed(9)),
                        ..Style::default()
                    };
                    let clip = grid.rect();
                    for (row, line) in format!("render failed: {err}").lines().enumerate() {
                        grid.text(clip, 0, row as i32, line, style);
                    }
                }
            }
            self.shared.frames.set(frames);
            if changed {
                let (grid, cursor) = (self.shared.grid.borrow(), self.shared.cursor.get());
                let mut desk = self.shared.desk.borrow_mut();
                let shown = desk.frontends.iter_mut().find(|(id, _)| *id == client);
                if let Some((_, frontend)) = shown
                    && let Err(err) = frontend.present(&grid, cursor)
                {
                    self.shared.log(format!("frontend: {err:#}"));
                    // A terminal at the end of a connection that has closed.
                    if client != 0 {
                        gone.push(client);
                    }
                }
            }
            kept.cursor = self.shared.cursor.get();
            std::mem::swap(&mut *self.shared.grid.borrow_mut(), &mut kept.grid);
            self.shared.desk.borrow_mut().kept.insert(client, kept);
        }
        self.enter(0);
        for client in gone {
            self.detach(client);
        }
    }
}
