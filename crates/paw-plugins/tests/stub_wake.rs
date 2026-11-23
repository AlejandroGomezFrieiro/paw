//! A CLAP plugin that asks the host for something from outside a block
//! while the engine rests: stopped, with nothing that sounds, the engine
//! runs no device until something wakes it (TASK-201). The stub plugin
//! (examples/stub_clap.rs) asks for a block on `stub.tell`, and for a
//! restart on `stub.restart`.
//!
//! A file of its own: the stub keeps the values it tells in statics, which
//! the tests in stub.rs and stub_state.rs read and hold.

use paw_engine::{
    Controller, DeviceSlot, Engine, EngineHandle, MAX_BLOCK, Msg, Registry, SchedEntry, Schedule,
    TrackRt, TrackSlot,
};
use paw_plugins::PluginDirs;
use tempfile::TempDir;

const DEVICE: DeviceSlot = DeviceSlot(0);

/// A directory holding the stub, as `stub.clap`. `cargo test` builds the
/// examples beside the tests.
fn stub_dir() -> TempDir {
    let exe = std::env::current_exe().unwrap();
    let built = exe
        .parent()
        .and_then(|deps| deps.parent())
        .unwrap()
        .join("examples/libstub_clap.so");
    assert!(
        built.exists(),
        "{} is built by `cargo test`",
        built.display()
    );
    let dir = tempfile::tempdir().unwrap();
    std::fs::copy(&built, dir.path().join("stub.clap")).unwrap();
    dir
}

/// An engine with the stub on one track, stopped, and the stub's
/// controller, as the session has them: the controller keeps the engine's
/// waker.
struct Rig {
    engine: Engine,
    _handle: EngineHandle,
    controller: Box<dyn Controller>,
    _dir: TempDir,
}

impl Rig {
    fn new() -> Self {
        let dir = stub_dir();
        let mut registry = Registry::default();
        let mut dirs = PluginDirs::default();
        let (kinds, notes) = paw_plugins::add_dir(&mut registry, None, &mut dirs, dir.path());
        assert_eq!(
            kinds,
            ["clap:dev.paw.stub"],
            "the stub is found ({notes:?})"
        );
        let instance = registry
            .get(&kinds[0])
            .unwrap()
            .create(48000.0, MAX_BLOCK)
            .unwrap();
        let mut controller = instance.controller.unwrap();

        let (mut engine, mut handle) = Engine::new(48000.0);
        controller.set_waker(handle.waker());
        let track = TrackSlot(1);
        let messages = [
            Msg::InsertTrack {
                slot: track,
                track: TrackRt::new(),
            },
            Msg::InsertDevice {
                slot: DEVICE,
                device: instance.device,
            },
            Msg::SetChain {
                track,
                chain: Box::new([DEVICE]),
            },
            Msg::SetSchedule(Box::new(Schedule::new(
                vec![
                    SchedEntry::new(track, TrackSlot::MASTER),
                    SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
                ],
                0,
            ))),
        ];
        for msg in messages {
            handle.send_while(msg, &mut engine);
        }
        Self {
            engine,
            _handle: handle,
            controller,
            _dir: dir,
        }
    }

    /// One callback of 256 frames.
    fn callback(&mut self) {
        let (mut left, mut right) = ([0.0f32; 256], [0.0f32; 256]);
        self.engine.process(&mut left, &mut right);
    }

    /// Blocks the stub has run.
    fn runs(&self) -> u64 {
        self.engine.shared().device_processed(DEVICE)
    }

    /// Run callbacks until the engine rests: the stub, with no note,
    /// sleeps, then the engine. Then one more callback runs no block of the
    /// stub.
    fn rest(&mut self) {
        let rests = self.engine.shared().engine_rests();
        for _ in 0..64 {
            self.callback();
            if self.engine.shared().engine_rests() > rests {
                break;
            }
        }
        assert!(
            self.engine.shared().engine_rests() > rests,
            "the engine rests"
        );
        let runs = self.runs();
        self.callback();
        assert_eq!(
            self.runs(),
            runs,
            "a resting engine runs no block of the stub"
        );
    }
}

#[test]
fn a_plugin_that_asks_for_a_block_while_the_engine_rests_gets_the_next_block() {
    let mut rig = Rig::new();
    rig.rest();
    let runs = rig.runs();

    // The plugin changes by itself and asks for a block (`request_process`).
    rig.controller.call("stub.tell", b"5").unwrap();
    rig.callback();

    assert_eq!(rig.runs(), runs + 1, "the next callback runs the stub");
}

#[test]
fn a_plugin_that_asks_for_a_restart_is_activated_again_and_gets_the_next_block() {
    let mut rig = Rig::new();
    let activations = |rig: &mut Rig| rig.controller.call("stub.activations", b"").unwrap();
    assert_eq!(activations(&mut rig), b"1", "activated once when made");
    rig.rest();
    let runs = rig.runs();

    // The plugin asks for a restart (`request_restart`); the host does it
    // on the main thread, in its idle.
    rig.controller.call("stub.restart", b"1").unwrap();
    rig.controller.idle();
    rig.callback();

    assert_eq!(activations(&mut rig), b"2", "activated again");
    assert_eq!(rig.controller.health(), None, "the plugin works");
    assert_eq!(rig.runs(), runs + 1, "the next callback runs the stub");
}
