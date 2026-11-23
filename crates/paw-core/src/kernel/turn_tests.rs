//! The order of a turn (docs/reference/the-order-of-a-turn.md) is the
//! same through `Kernel::run` and through `paw.api.step`: both take the
//! one turn of the reactor. And the wait between two turns: a quiet
//! kernel sleeps with no limit, and a missed wake is counted.

use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use mlua::Lua;
use paw_engine::backend::{BackendChoice, BackendOptions};
use paw_engine::Registry;
use paw_proto::dirs::Dirs;

use super::reactor::Reactor;
use super::{Frontend, InputEvent, Kernel, KernelMsg, KernelOpts};
use crate::api;
use crate::clock::{Agenda, Clock};
use crate::doorbell::Woken;
use crate::grid::Grid;

/// What the kernel did, in the order it did it.
type Log = Rc<RefCell<Vec<String>>>;

/// A frontend that notes each frame it is shown.
struct Recording(Log);

impl Frontend for Recording {
    fn present(&mut self, _: &Grid, _: Option<(u16, u16)>) -> anyhow::Result<()> {
        self.0.borrow_mut().push("frame".into());
        Ok(())
    }
}

/// The kernel's hooks in Lua, each of which notes that it ran. A key asks
/// for a frame, as the runtime's does.
const HOOKS: &str = r#"
paw = { api = require("paw.api") }
paw._kernel = {
  seat = function() end,
  key = function(key) note("key " .. key); paw.api.ui_redraw() end,
  timer = function(fn) note("timer"); fn() end,
  close_turn = function() note("close the turn") end,
  render = function() note("draw") end,
  exit = function() end,
}
"#;

/// A kernel on the null backend and the manual clock, in a scratch home,
/// with the hooks of [`HOOKS`] and a [`Recording`] frontend.
fn kernel(home: &tempfile::TempDir, log: &Log) -> Kernel {
    let at = |name: &str| Some(home.path().join(name));
    let mut kernel = Kernel::new(KernelOpts {
        backend: BackendOptions { backend: BackendChoice::Null, ..Default::default() },
        registry: Registry::with_builtins(),
        config_dir: home.path().join("config"),
        runtime_dir: None,
        home: None,
        dirs: Dirs { config: at("config"), data: at("data"), state: at("state"), cache: at("cache"), runtime: at("run") },
        clean: true,
        scripted: true,
        argv: Vec::new(),
        clock: Clock::manual(),
    })
    .unwrap();
    let lua = Lua::new();
    api::install(&lua, &kernel.shared).unwrap();
    let noted = log.clone();
    let note = lua.create_function(move |_, what: String| {
        noted.borrow_mut().push(what);
        Ok(())
    });
    lua.globals().set("note", note.unwrap()).unwrap();
    lua.load(HOOKS).exec().unwrap();
    kernel.lua = lua;
    kernel.attach(Box::new(Recording(log.clone())), 80, 24);
    kernel
}

/// A key and a timer due now: the work of one turn.
fn key_and_timer(kernel: &Kernel, then: &str) {
    kernel.sender().send(KernelMsg::Input(InputEvent::Key("a".into()))).unwrap();
    let timer = format!("paw.api.timer_start(0, false, function() {then} end)");
    kernel.lua.load(timer).exec().unwrap();
}

/// The steps of one turn, as the hooks note them.
const ONE_TURN: [&str; 3] = ["key a", "timer", "close the turn"];

#[test]
fn a_turn_through_run_and_through_api_step_runs_the_same_steps_in_the_same_order() {
    let home = tempfile::tempdir().unwrap();
    let log = Log::default();
    let mut run = kernel(&home, &log);
    // The timer starts one more at the same instant, which quits: the loop
    // takes a second turn and stops.
    key_and_timer(&run, "paw.api.timer_start(0, false, function() paw.api.quit(0) end)");
    assert_eq!(run.run().unwrap(), 0);
    let through_run = log.take();
    assert_eq!(
        through_run,
        ["draw", "frame", ONE_TURN[0], ONE_TURN[1], ONE_TURN[2], "draw", "frame", "timer", "close the turn"],
        "the first frame, the turn, the frame it asked for, and the turn that quits"
    );

    let home = tempfile::tempdir().unwrap();
    let log = Log::default();
    let step = kernel(&home, &log);
    key_and_timer(&step, "");
    step.lua.load("paw.api.step()").exec().unwrap();
    assert_eq!(log.take(), ONE_TURN, "api.step takes the same turn, and draws nothing");
}

#[test]
fn a_settled_kernel_with_no_work_sleeps_until_a_message_or_a_ring() {
    let home = tempfile::tempdir().unwrap();
    let log = Log::default();
    let kernel = kernel(&home, &log);
    let quiet: bool = kernel
        .lua
        .load("local p = paw.api.settle(); return p.quiet and not p.ready and p.next_ms == nil and next(p.in_flight) == nil")
        .eval()
        .unwrap();
    assert!(quiet, "settle leaves nothing ready, in flight or due");
    let now = kernel.shared.clock.now();
    let agenda = kernel.reactor().agenda(now);
    assert_eq!(Reactor::sleep_for(&agenda, now), (None, false), "no timeout");
}

#[test]
fn the_wait_is_until_the_next_due_time_a_tick_or_the_safety_tick_whichever_is_first() {
    let now = crate::clock::ScheduleTime::ZERO;
    let at = |ms| now + Duration::from_millis(ms);
    let in_flight = Agenda { in_flight: 1, ..Agenda::default() };
    assert_eq!(Reactor::sleep_for(&in_flight, now), (Some(Duration::from_millis(250)), true), "work in flight");
    let ticking = Agenda { tick: Some(Duration::from_millis(16)), ..in_flight };
    assert_eq!(Reactor::sleep_for(&ticking, now), (Some(Duration::from_millis(16)), false), "a part that asks for a tick");
    let due = Agenda { next_due: Some(at(40)), ..Agenda::default() };
    assert_eq!(Reactor::sleep_for(&due, now), (Some(Duration::from_millis(40)), false), "a due time");
    let ready = Agenda { ready: true, ..due };
    assert_eq!(Reactor::sleep_for(&ready, now), (Some(Duration::ZERO), false), "work ready now");
}

#[test]
fn an_idle_timer_that_is_due_is_not_work_that_settle_waits_for() {
    let home = tempfile::tempdir().unwrap();
    let log = Log::default();
    let kernel = kernel(&home, &log);
    let (ready, quiet, next_ms): (bool, bool, f64) = kernel
        .lua
        .load("paw.api.timer_start(0, false, function() end, true); local p = paw.api.pending(); return p.ready, p.quiet, p.next_ms")
        .eval()
        .unwrap();
    assert_eq!((ready, quiet, next_ms), (false, true, 0.0), "due now, and not ready");
    kernel.lua.load("paw.api.settle()").exec().unwrap();
    assert_eq!(log.take(), ["timer", "close the turn"], "the turn of the settle fires it");
}

#[test]
fn news_with_no_ring_after_the_safety_tick_is_a_missed_wake() {
    let home = tempfile::tempdir().unwrap();
    let log = Log::default();
    let kernel = kernel(&home, &log);
    let reactor = kernel.reactor();
    let after_a_tick = |woken, news| {
        kernel.shared.looked_on_a_tick.set(true);
        reactor.note_missed_wakes(woken, news);
    };
    after_a_tick(Woken::BAKES, Woken::BAKES);
    after_a_tick(Woken::empty(), Woken::PLUGINS);
    assert_eq!(kernel.shared.missed_wakes.get(), 0, "a ring, and news that rings no bell");
    after_a_tick(Woken::empty(), Woken::BAKES);
    assert_eq!(kernel.shared.missed_wakes.get(), 1, "a bake that ended with no ring");
    reactor.note_missed_wakes(Woken::empty(), Woken::BAKES);
    assert_eq!(kernel.shared.missed_wakes.get(), 1, "news found after a ring of another kind is no miss");
    let counted: u64 = kernel.lua.load("return paw.api.pending().missed_wakes").eval().unwrap();
    assert_eq!(counted, 1);
}
