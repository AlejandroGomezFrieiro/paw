//! `paw.api`: timers, the schedule clock, one turn of the loop, time
//! limits, and the kernel's quit, reload and log.

use std::rc::Rc;
use std::time::{Duration, Instant};

use mlua::{Function, Lua, Table};
use serde::Serialize;

use crate::clock::{Clock, ManualClock};
use crate::watchdog::Watchdog;

use super::{Shared, Timer};

/// How often a wait on the wall clock looks after the plugins
/// (`Session::idle`): their editors draw from there.
const IDLE_PERIOD: Duration = Duration::from_millis(15);
/// The turns at one instant of the manual clock before it moves on. A job
/// that looks again at no delay (`paw.defer(fn, 0)`) for a state that a
/// later timer makes is due at each turn: without this limit the clock
/// never gets to that timer.
const TURNS_AT_ONE_INSTANT: u32 = 1000;
/// The most schedule time between two turns while the engine is stepped
/// (about ten blocks): what it played is heard of, and a take is written,
/// before it plays more.
const AUDIO_TURN: Duration = Duration::from_millis(100);

/// The functions of the timers that are due, with one-shot timers removed
/// and repeating ones moved on.
pub(crate) fn due_timers(shared: &Shared) -> Vec<Rc<mlua::RegistryKey>> {
    let now = shared.clock.now();
    let mut timers = shared.timers.borrow_mut();
    let mut due = Vec::new();
    timers.retain_mut(|timer| {
        if timer.due > now {
            return true;
        }
        due.push(timer.func.clone());
        match timer.repeat {
            Some(period) => {
                // Skip missed periods rather than firing in a burst.
                timer.due = (timer.due + period).max(now);
                true
            }
            None => false,
        }
    });
    due
}

/// The work that is not done yet (`paw.api.pending`): what the next turn
/// does, what other threads and processes do now, and what waits for the
/// schedule clock.
#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize)]
pub(crate) struct Pending {
    /// Timers due now: the next turn fires them.
    pub timers_due: usize,
    /// All the timers, also the ones that wait for the clock.
    pub timers: usize,
    /// Milliseconds of schedule time until the next timer or settle delay
    /// is due; none when nothing waits for the clock.
    pub next_ms: Option<f64>,
    /// Bakes being made on other threads or in helper processes.
    pub bakes_running: usize,
    /// Bakes that wait for their settle on the schedule clock.
    pub bakes_waiting: usize,
    /// Files of stretched clips being hashed: their bakes are asked for
    /// after.
    pub hashing: usize,
    /// Plugins being made apart from the main loop.
    pub plugin_loads: usize,
    /// Renders running on a thread of their own.
    pub renders: usize,
    /// Files changed outside paw that wait for their settle.
    pub files: usize,
    /// MIDI that came in from ports and is not heard yet.
    pub midi: usize,
    /// Helper processes at work: piped ones that have not closed their
    /// output, and others that still run.
    pub helpers: usize,
}

impl Shared {
    /// One turn of the loop of a script: fire the timers that are due,
    /// look after the plugins (when `idle`), hear MIDI and the output of
    /// helpers, push the edits and close the undo step. Nothing waits.
    pub(crate) fn turn(&self, lua: &Lua, idle: bool) -> mlua::Result<()> {
        let kernel: Table = lua.globals().get::<Table>("paw")?.get("_kernel")?;
        let (timer, settle): (Function, Function) = (kernel.get("timer")?, kernel.get("settle")?);
        for func in due_timers(self) {
            timer.call::<()>(lua.registry_value::<Function>(&func)?)?;
        }
        // Plugins are looked after as they are while the program runs.
        if idle {
            self.session.borrow_mut().idle();
        }
        // What was played into a port, or written by a helper, meanwhile
        // is heard of.
        self.hear_midi();
        self.hear_output();
        settle.call::<()>(())?;
        self.session.borrow_mut().checkpoint();
        Ok(())
    }

    /// The work that is not done yet.
    pub(crate) fn pending(&self) -> Pending {
        let now = self.clock.now();
        let (timers_due, timers) = {
            let timers = self.timers.borrow();
            (timers.iter().filter(|t| t.due <= now).count(), timers.len())
        };
        let work = self.session.borrow().work();
        Pending {
            timers_due,
            timers,
            next_ms: self.next_due_after(now).map(|due| super::as_ms(due - now)),
            bakes_running: work.bakes_running,
            bakes_waiting: work.bakes_waiting,
            hashing: work.hashing,
            plugin_loads: work.plugin_loads,
            renders: work.renders,
            files: work.files,
            midi: self.midi_in.lock().unwrap().len(),
            helpers: self.io.borrow_mut().working(),
        }
    }

    /// The first time after `now` on the schedule clock when a timer or a
    /// settle delay of the session is due.
    fn next_due_after(&self, now: Duration) -> Option<Duration> {
        let timer = self.timers.borrow().iter().map(|t| t.due).filter(|&due| due > now).min();
        let work = self.session.borrow().work().next_due.filter(|&due| due > now);
        timer.into_iter().chain(work).min()
    }

    /// Let `by` of schedule time pass on the manual clock: move the clock
    /// from one due time to the next, with a turn at each, so that each
    /// timer fires in its order and sees its own time. A stepped engine
    /// plays the blocks of that time in the turns (`Session::idle`).
    fn advance(&self, lua: &Lua, clock: &ManualClock, by: Duration) -> mlua::Result<()> {
        let target = clock.now() + by;
        let mut turns_here = 0;
        loop {
            self.turn(lua, true)?;
            let now = clock.now();
            // A turn can start a timer that is due at once (`paw.defer`).
            turns_here += 1;
            if turns_here < TURNS_AT_ONE_INSTANT && self.timers.borrow().iter().any(|t| t.due <= now) {
                continue;
            }
            turns_here = 0;
            let mut next = self.next_due_after(now);
            if self.session.borrow().is_audio_stepped() {
                let audio = now + AUDIO_TURN;
                next = Some(next.map_or(audio, |due| due.min(audio)));
            }
            match next {
                Some(due) if due <= target => clock.advance_to(due),
                _ => break,
            }
        }
        clock.advance_to(target);
        self.turn(lua, true)
    }

    /// Let `by` of wall time pass, with a turn each millisecond.
    fn wait_on_the_wall(&self, lua: &Lua, by: Duration) -> mlua::Result<()> {
        let deadline = Instant::now() + by;
        let mut idled: Option<Instant> = None;
        loop {
            let idle = idled.is_none_or(|at| at.elapsed() >= IDLE_PERIOD);
            if idle {
                idled = Some(Instant::now());
            }
            self.turn(lua, idle)?;
            if Instant::now() >= deadline {
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- timers ---
        // @return integer
        // @param func function()
        fn timer_start(lua, sh, (ms, repeat, func) => (f64, bool, Function)) {
            let func = Rc::new(lua.create_registry_value(func)?);
            let id = sh.next_timer.get() + 1;
            sh.next_timer.set(id);
            let period = super::millis(ms);
            // A repeating timer with no period would starve everything else.
            let repeat = repeat.then(|| period.max(Duration::from_millis(1)));
            sh.timers.borrow_mut().push(Timer { id, due: sh.clock.now() + period, repeat, func });
            Ok(id)
        }
        // @return nil
        fn timer_stop(_, sh, id => u64) {
            sh.timers.borrow_mut().retain(|t| t.id != id);
            Ok(())
        }
        // The schedule time in milliseconds since paw started: the time
        // that timers, delays and throttles wait for. In a test that runs
        // with `paw --clock manual`, it moves only when the test waits. To
        // measure how long work takes, use `real_ms`.
        // @return number
        fn now(_, sh, () => ()) { Ok(super::as_ms(sh.clock.now())) }
        // The time on the wall in milliseconds since paw started, for a
        // budget of work or a deadline for another process. It moves also
        // in a test. For a delay or a throttle, use `now`.
        // @return number
        fn real_ms(_, sh, () => ()) { Ok(super::as_ms(sh.started.elapsed())) }
        // The time limit on Lua (`paw.limit`). The arguments are the function to
        // call when a callback runs too long, and the time when the current
        // callback must return (on the clock of `real_ms`, nil when it returned).
        // `limit_async` tells if paw finds an overrun inside compiled code too.
        // @param func function()
        // @return nil
        fn limit_hook(lua, _sh, func => Function) { Watchdog::set_hook(lua, func) }
        // @return nil
        fn limit_watch(_, sh, deadline => Option<f64>) {
            sh.watchdog.watch(deadline);
            Ok(())
        }
        // @return nil
        fn sleep(_, _sh, ms => f64) {
            std::thread::sleep(super::millis(ms));
            Ok(())
        }
        // Let `ms` milliseconds pass. Timers fire and events come, as between the
        // key presses of a person. `sleep` stops all of that. A script that waits
        // for the result of a timer uses `wait`. With `paw --clock manual`, the
        // time passes at once: each timer fires in its order, at its own time.
        // @return nil
        fn wait(lua, sh, ms => f64) {
            match sh.clock.manual() {
                Some(clock) => sh.advance(lua, clock, super::millis(ms)),
                None => sh.wait_on_the_wall(lua, super::millis(ms)),
            }
        }
        // Do one turn of the loop and return at once: fire the timers that are
        // due, look after the plugins, take in MIDI and the output of helper
        // processes, and close the undo step. No time passes.
        // @return nil
        fn step(lua, sh, () => ()) { sh.turn(lua, true) }
        // On the stepped audio backend (`paw --audio step --clock manual`,
        // the tests), let the time of `blocks` audio blocks pass: the clock
        // moves to the end of the last of them, the timers due on the way
        // fire, and the engine plays exactly that many blocks. Gives the
        // number of blocks, or 0 when the engine plays on its own and
        // nothing was done.
        // @return integer
        fn wait_blocks(lua, sh, blocks => u64) {
            let end = sh.session.borrow().stepped_end_of(blocks);
            match (end, sh.clock.manual()) {
                (Some(end), Some(clock)) => {
                    sh.advance(lua, clock, end.saturating_sub(clock.now()))?;
                    Ok(blocks)
                }
                _ => Ok(0),
            }
        }
        // The work that is not done yet, by kind: timers due now and all the
        // timers, the time until the next timer or delay is due (`next_ms`),
        // bakes, files of stretched clips being hashed, plugins being loaded,
        // renders, changed files, MIDI that came in, and helper processes. A
        // test waits until nothing is in flight.
        // @return types.Pending
        fn pending(lua, sh, () => ()) { super::to_lua(lua, &sh.pending()) }

        // --- kernel ---
        // @return nil
        fn quit(_, sh, code => Option<i32>) {
            sh.quit.set(Some(code.unwrap_or(0)));
            Ok(())
        }
        // @return nil
        fn reload(_, sh, () => ()) {
            sh.reload.set(true);
            Ok(())
        }
        // @return nil
        fn log(_, sh, line => String) {
            sh.log(line);
            Ok(())
        }
    }
    Ok(())
}
