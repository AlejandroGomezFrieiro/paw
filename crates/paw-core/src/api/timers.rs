//! `paw.api`: timers, time limits, and the kernel's quit, reload and log.

use std::rc::Rc;
use std::time::{Duration, Instant};

use mlua::{Function, Lua, Table};

use crate::watchdog::Watchdog;

use super::{Shared, Timer};

/// The functions of the timers that are due, with one-shot timers removed
/// and repeating ones moved on.
pub fn due_timers(shared: &Shared) -> Vec<Rc<mlua::RegistryKey>> {
    let now = Instant::now();
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

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- timers ---
        // @return integer
        // @param func function()
        fn timer_start(lua, sh, (ms, repeat, func) => (f64, bool, Function)) {
            let func = Rc::new(lua.create_registry_value(func)?);
            let id = sh.next_timer.get() + 1;
            sh.next_timer.set(id);
            let period = Duration::from_secs_f64(ms.max(0.0) / 1000.0);
            // A repeating timer with no period would starve everything else.
            let repeat = repeat.then(|| period.max(Duration::from_millis(1)));
            sh.timers.borrow_mut().push(Timer { id, due: Instant::now() + period, repeat, func });
            Ok(id)
        }
        // @return nil
        fn timer_stop(_, sh, id => u64) {
            sh.timers.borrow_mut().retain(|t| t.id != id);
            Ok(())
        }
        // @return number
        fn now(_, sh, () => ()) { Ok(sh.started.elapsed().as_secs_f64() * 1000.0) }
        // The time limit on Lua (`paw.limit`). The arguments are the function to
        // call when a callback runs too long, and the time when the current
        // callback must return (on the clock of `now`, nil when it returned).
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
            std::thread::sleep(Duration::from_secs_f64(ms.max(0.0) / 1000.0));
            Ok(())
        }
        // Let `ms` milliseconds pass. Timers fire and events come, as between the
        // key presses of a person. `sleep` stops all of that. A script that waits
        // for the result of a timer uses `wait`.
        // @return nil
        fn wait(lua, sh, ms => f64) {
            let deadline = Instant::now() + Duration::from_secs_f64(ms.max(0.0) / 1000.0);
            let kernel: Table = lua.globals().get::<Table>("paw")?.get("_kernel")?;
            let (timer, settle): (Function, Function) = (kernel.get("timer")?, kernel.get("settle")?);
            let mut idled = Instant::now() - Duration::from_secs(1);
            loop {
                for func in due_timers(&sh) {
                    timer.call::<()>(lua.registry_value::<Function>(&func)?)?;
                }
                // Plugins are looked after as they are while the program runs.
                if idled.elapsed() >= Duration::from_millis(15) {
                    sh.session.borrow_mut().idle();
                    idled = Instant::now();
                }
                // What was played into a port, or written by a helper,
                // meanwhile is heard of.
                sh.hear_midi();
                sh.hear_output();
                settle.call::<()>(())?;
                sh.session.borrow_mut().checkpoint();
                if Instant::now() >= deadline {
                    return Ok(());
                }
                std::thread::sleep(Duration::from_millis(1));
            }
        }

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
