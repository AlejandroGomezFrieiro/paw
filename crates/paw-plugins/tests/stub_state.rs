//! A state given to the stub CLAP plugin (examples/stub_clap.rs) while one
//! of its blocks is under way. The plugin takes a state on at the start of
//! a block, as Surge XT does: the block under way does not take it, and the
//! host reads the plugin's values back only after the next block.
//! (the host read them after the block under way, found the old
//! values, and never read them again.)

#![expect(
    clippy::unwrap_used,
    reason = "test code: a failed unwrap is a failed test"
)]

use paw_engine::device::{Change, Instance};
use paw_engine::{EventBuf, Io, ProcessCtx, Registry};
use paw_plugins::PluginDirs;
use tempfile::TempDir;

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

#[test]
fn a_state_given_while_a_block_runs_is_read_back_after_the_next_block() {
    let dir = stub_dir();
    let mut registry = Registry::default();
    let mut dirs = PluginDirs::default();
    let (kinds, notes) = paw_plugins::add_dir(&mut registry, None, &mut dirs, dir.path());
    assert_eq!(
        kinds,
        ["clap:dev.paw.stub"],
        "the stub is found ({notes:?})"
    );
    let Instance {
        mut device,
        controller,
    } = registry
        .get(&kinds[0])
        .unwrap()
        .create(48000.0, 256)
        .unwrap();
    let mut controller = controller.unwrap();
    // SAFETY: the stub plugin is a library of this workspace that runs no code when it loads.
    let lib = unsafe { libloading::Library::new(dir.path().join("stub.clap")).unwrap() };
    let held: libloading::Symbol<extern "C" fn() -> bool> =
        // SAFETY: `stub_clap_held` has this signature in the stub plugin.
        unsafe { lib.get(b"stub_clap_held\0").unwrap() };
    let release: libloading::Symbol<extern "C" fn()> =
        // SAFETY: `stub_clap_release` has this signature in the stub plugin.
        unsafe { lib.get(b"stub_clap_release\0").unwrap() };

    let ctx = ProcessCtx::at(48000.0, 120.0, 4, 4, false);
    let (mut left, mut right) = (vec![0.0; 256], vec![0.0; 256]);
    let mut events = EventBuf::with_capacity(4);
    let mut block = move || {
        device.process(
            &ctx,
            &mut Io {
                left: &mut left,
                right: &mut right,
                events: &mut events,
                sidechain: None,
                outputs: &mut [],
            },
        );
    };
    // The plugin tells nothing of a state it takes on: only a read of its
    // values finds it.
    controller.call("stub.quiet", b"1").unwrap();
    // The first block and read only record where the values stand.
    block();
    assert_eq!(controller.take_changes(), []);

    // The state comes while a block that already looked for one waits.
    controller.call("stub.hold", b"1").unwrap();
    std::thread::scope(|scope| {
        let under_way = scope.spawn(&mut block);
        while !held() {
            std::thread::yield_now();
        }
        controller.load_state(&7u32.to_le_bytes()).unwrap();
        release();
        under_way.join().unwrap();
    });
    assert_eq!(
        controller.take_changes(),
        [],
        "the block under way did not take the state on"
    );

    block();
    assert_eq!(
        controller.take_changes(),
        [Change {
            index: 0,
            value: 7.0,
            edit: false,
        }],
        "after the next block, the state's value is read back as its echo"
    );
}
