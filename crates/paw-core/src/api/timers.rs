//! `paw.api`: timers, the schedule clock, one turn of the loop, time
//! limits, and the kernel's quit, reload and log.

use std::rc::Rc;
use std::time::Duration;

use mlua::{Function, Lua, Table};
use serde::Serialize;

use crate::clock::ScheduleTime;
use crate::kernel::Reactor;
use crate::watchdog::Watchdog;

use super::{LuaResult, Shared, Timer};

/// The most sound that one `wait_blocks` plays: a count past it is a
/// mistake, which would keep the main loop busy for ever.
const MOST_BLOCKS_TIME: Duration = Duration::from_secs(60);

/// The functions of the timers due at `now`, with one-shot timers removed
/// and repeating ones moved on.
pub(crate) fn due_timers(shared: &Shared, now: ScheduleTime) -> Vec<Rc<mlua::RegistryKey>> {
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
    /// Measurements of the mix running on threads of their own.
    pub measures: usize,
    /// Files changed outside paw that wait for their settle.
    pub files: usize,
    /// MIDI that came in from ports and is not heard yet.
    pub midi: usize,
    /// Helper processes at work: piped ones that have not closed their
    /// output, and others that still run.
    pub helpers: usize,
    /// The helpers that paw waits for: a program that has not answered
    /// what paw wrote to it, or one that works on its own until it ends.
    /// A language server that answered and waits for more is not counted.
    pub helpers_busy: usize,
}

impl Shared {
    /// The work that is not done yet.
    pub(crate) fn pending(&self, lua: &Lua) -> Pending {
        let now = self.clock.now();
        let (timers_due, timers) = {
            let timers = self.timers.borrow();
            (timers.iter().filter(|t| t.due <= now).count(), timers.len())
        };
        let next_due = Reactor::new(self, lua).agenda(now).next_due;
        let work = self.session.borrow().work();
        // One borrow each: a struct literal keeps its temporaries to the end,
        // so two `borrow_mut` calls in it would clash.
        let midi = self.midi_in.lock().unwrap().len();
        let (helpers, helpers_busy) = {
            let mut io = self.io.borrow_mut();
            (io.working(), io.awaited())
        };
        Pending {
            timers_due,
            timers,
            next_ms: next_due.map(|due| super::as_ms(due - now)),
            bakes_running: work.bakes_running,
            bakes_waiting: work.bakes_waiting,
            hashing: work.hashing,
            plugin_loads: work.plugin_loads,
            renders: work.renders,
            measures: self.measures.count(),
            files: work.files,
            midi,
            helpers,
            helpers_busy,
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
        fn now(_, sh, () => ()) { Ok(sh.clock.now().as_ms()) }
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
        fn wait(lua, sh, ms => f64) { Reactor::new(&sh, lua).wait_for(super::millis(ms)).lua() }
        // Do one turn of the loop and return at once: fire the timers that are
        // due, look after the plugins, take in MIDI and the output of helper
        // processes, and close the undo step. No time passes.
        // @return nil
        fn step(lua, sh, () => ()) {
            let _ = Reactor::new(&sh, lua).turn(sh.clock.now());
            Ok(())
        }
        // On the stepped audio backend (`paw --audio step --clock manual`,
        // the tests), let the time of `blocks` audio blocks pass: the clock
        // moves to the end of the last of them, the timers due on the way
        // fire, and the engine plays exactly that many blocks. Gives the
        // number of blocks. On another backend or clock, and for more than
        // 60 seconds of blocks, it is an error.
        // @return integer
        fn wait_blocks(lua, sh, blocks => u64) {
            let end = sh.session.borrow().stepped_end_of(blocks);
            let Some(end) = end.filter(|_| sh.clock.is_manual()) else {
                return Err(mlua::Error::runtime(
                    "wait_blocks needs the stepped audio backend and the manual clock (paw --audio step --clock manual)",
                ));
            };
            let time = end - sh.clock.now();
            if time > MOST_BLOCKS_TIME {
                return Err(mlua::Error::runtime(format!(
                    "wait_blocks plays at most {} s of blocks, not {blocks} blocks",
                    MOST_BLOCKS_TIME.as_secs()
                )));
            }
            Reactor::new(&sh, lua).advance(time);
            Ok(blocks)
        }
        // The work that is not done yet, by kind: timers due now and all the
        // timers, the time until the next timer or delay is due (`next_ms`),
        // bakes, files of stretched clips being hashed, plugins being loaded,
        // renders, measurements, changed files, MIDI that came in, and helper
        // processes. A test waits until nothing is in flight.
        // @return types.Pending
        fn pending(lua, sh, () => ()) { super::to_lua(lua, &sh.pending(lua)) }

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
