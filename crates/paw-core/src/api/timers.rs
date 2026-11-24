//! `paw.api`: timers, the schedule clock, one turn of the loop, time
//! limits, and the kernel's quit, reload and log.

#![expect(
    clippy::unwrap_used,
    reason = "debt: pay down"
)]

use std::collections::BTreeMap;
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
#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub(crate) struct Pending {
    /// The next turn has work: a timer is due, a message came, a delay
    /// ended. An idle timer is not work.
    pub ready: bool,
    /// Nothing is in flight, no helper process is at work, no plugin works
    /// or owes its new state (`plugins_busy`, `plugins_owe`), and the engine
    /// plays nothing that changes the state: only the timers are left, the
    /// ones due now (`ready`) and the ones that wait for the clock
    /// (`next_ms`). After `settle`, a timer due now is a job that looks
    /// again and again at no delay.
    pub quiet: bool,
    /// Milliseconds of schedule time until the next timer or settle delay
    /// is due; none when nothing waits for the clock.
    pub next_ms: Option<f64>,
    /// The work in flight on other threads and in other processes, by
    /// kind: `bakes`, `hashes`, `loads` (plugins), `renders`, `takes`
    /// (their writers), `preview`, `measures`. A kind with none is left out.
    pub in_flight: BTreeMap<&'static str, u32>,
    /// Timers due now: the next turn fires them.
    pub timers_due: usize,
    /// All the timers, also the ones that wait for the clock.
    pub timers: usize,
    /// Bakes that wait for their settle on the schedule clock.
    pub bakes_waiting: usize,
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
    /// Plugins with a thread of their own at work now (a model that loads,
    /// an analysis): what it makes comes in a later block, so the stepped
    /// engine waits for it.
    pub plugins_busy: usize,
    /// Plugins that took a request (a model, a preset of their own) and
    /// have not shown their new state yet: their next blocks show it.
    pub plugins_owe: usize,
    /// How many times a turn found the result of a worker that did not
    /// ring the loop: it waited for the safety tick. A bug of that worker;
    /// the log names its kind.
    pub missed_wakes: u64,
}

impl Shared {
    /// The work that is not done yet.
    pub(crate) fn pending(&self, lua: &Lua) -> Pending {
        let now = self.clock.now();
        let (timers_due, timers) = {
            let timers = self.timers.borrow();
            (timers.iter().filter(|t| t.due <= now).count(), timers.len())
        };
        let agenda = Reactor::new(self, lua).agenda(now);
        // To ask an attachment whether its plugin works takes the session
        // mutably. A caller that holds the session (a callback inside a
        // session call) gets the count of the plugins' threads only, and
        // none while the session is held mutably.
        let plugins_busy = match self.session.try_borrow_mut() {
            Ok(mut session) => session.plugins_busy(),
            Err(_) => self.session.try_borrow().map_or(0, |session| session.plugin_threads_busy()),
        };
        let (in_flight, waiting, plays, plugins_owe) = {
            let session = self.session.borrow();
            (session.in_flight(now), session.waiting(), session.plays(), session.plugins_owe())
        };
        let mut in_flight: BTreeMap<&'static str, u32> = in_flight.into_iter().collect();
        let measures = u32::try_from(self.measures.count()).unwrap_or(u32::MAX);
        if measures > 0 {
            in_flight.insert("measures", measures);
        }
        // One borrow each: a struct literal keeps its temporaries to the end,
        // so two `borrow_mut` calls in it would clash.
        let midi = self.midi_in.lock().unwrap().len();
        let (helpers, helpers_busy) = {
            let mut io = self.io.borrow_mut();
            (io.working(), io.awaited())
        };
        Pending {
            ready: agenda.ready,
            quiet: agenda.in_flight == 0 && helpers == 0 && !plays && plugins_busy == 0 && plugins_owe == 0,
            next_ms: agenda.next_due.map(|due| super::as_ms(due - now)),
            in_flight,
            timers_due,
            timers,
            bakes_waiting: waiting.bakes,
            files: waiting.files,
            midi,
            helpers,
            helpers_busy,
            plugins_busy,
            plugins_owe,
            missed_wakes: self.missed_wakes.get(),
        }
    }
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- timers ---

        // Start a timer: `func` runs after `ms` milliseconds, and again
        // each `ms` when `repeat` is true. An `idle` timer is idle work (the
        // collector of garbage): when it is due, a wait of a test
        // (`settle`) does not wait for it, and `pending().quiet` holds.
        // @return integer
        // @param func function()
        fn timer_start(lua, sh, (ms, repeat, func, idle) => (f64, bool, Function, Option<bool>)) {
            let func = Rc::new(lua.create_registry_value(func)?);
            let id = sh.next_timer.get() + 1;
            sh.next_timer.set(id);
            let period = super::millis(ms);
            // A repeating timer with no period would starve everything else.
            let repeat = repeat.then(|| period.max(Duration::from_millis(1)));
            let idle = idle.unwrap_or(false);
            sh.timers.borrow_mut().push(Timer { id, due: sh.clock.now() + period, repeat, idle, func });
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
        // The work that is not done yet: whether the next turn has work
        // (`ready`), whether only due times are left (`quiet`), the time
        // until the next timer or delay is due (`next_ms`), the work in
        // flight on other threads and processes by kind (`in_flight`), the
        // timers, the bakes and changed files that wait for their settle,
        // MIDI that came in, helper processes, the plugins that work on
        // their own threads or owe their new state (`plugins_busy`,
        // `plugins_owe`), and the wakes that a worker missed (`missed_wakes`).
        // @return types.Pending
        fn pending(lua, sh, () => ()) { super::to_lua(lua, &sh.pending(lua)) }
        // Turn the loop until nothing is ready and no work is in flight:
        // the timers due now fire, and the loop waits for the bakes, the
        // hashes, the plugin loads, the renders and the other work of
        // threads and processes to end. No schedule time passes, and an
        // idle timer is not waited for. Gives what `pending` gives then. It
        // fails when work is still in flight after 30 seconds.
        // @return types.Pending
        fn settle(lua, sh, () => ()) {
            let _ = Reactor::new(&sh, lua).settle().lua()?;
            super::to_lua(lua, &sh.pending(lua))
        }
        // The schedule clock of the process: "manual" when it moves only
        // when a script waits (`paw --clock manual`, the tests), else "wall".
        // @return string
        fn clock(_, sh, () => ()) { Ok(if sh.clock.is_manual() { "manual" } else { "wall" }) }

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
        // Write a line to the log (`:log`) at `level`: "error", "warn",
        // "info" (when not given), "debug" or "trace". Its target is `lua`.
        // `paw.api.log_get` keeps the last 1000 lines too.
        // @param level? string
        // @return nil
        fn log(_, sh, (line, level) => (String, Option<String>)) {
            let word = level.as_deref().unwrap_or("info");
            let Some(level) = crate::logging::level_of(word) else {
                return Err(mlua::Error::runtime(format!(
                    "{word:?} is not a level: error, warn, info, debug or trace"
                )));
            };
            crate::logging::lua(level, &line);
            sh.keep(line);
            Ok(())
        }
        // Set the levels of the log, as `paw.opt.loglevel` holds them:
        // `"info"`, or a level for each target, `"info,plugin=debug"`.
        // Returns nil, or the levels that `PAW_LOG` set for this run and
        // that stay. An error when the text is not a list of levels.
        // @return string
        fn log_level(_, _sh, spec => String) {
            match crate::logging::set_levels(&spec).map_err(mlua::Error::runtime)? {
                crate::logging::LevelChange::Set => Ok(None),
                crate::logging::LevelChange::KeptEnv(kept) => Ok(Some(kept)),
            }
        }
        // Whether `spec` is a list of levels for `paw.api.log_level`: nil,
        // or what is wrong with it.
        // @return string
        fn log_level_check(_, _sh, spec => String) {
            Ok(crate::logging::check_levels(&spec).err())
        }
        // The files of the log: `current` (`paw.log` of this run),
        // `previous` (the run before) and `stderr` (what plugins and
        // libraries printed in this run). Each is nil in a run with no log
        // file: a script writes none.
        // @return types.LogFiles
        fn log_files(lua, _sh, () => ()) {
            super::to_lua(lua, &crate::logging::files())
        }
        // Write the events of the flight recorder that the log file left
        // out to it (`:log dump`). Returns how many, or nil in a run with
        // no log file.
        // @return integer
        fn log_dump(_, _sh, () => ()) {
            Ok(crate::logging::dump(":log dump"))
        }
    }
    Ok(())
}
