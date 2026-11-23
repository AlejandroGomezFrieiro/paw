//! Hosting a CLAP plugin never allocates or frees on the audio thread:
//! the stub plugin (examples/stub_clap.rs, which allocates nothing itself)
//! is started and run through notes, a parameter, a state and a move in its
//! window, with a global allocator that counts what the audio thread does.
//! A file of its own: the stub keeps its notes in statics, which the test in
//! stub.rs reads.

use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

use paw_engine::{Event, EventBuf, Io, ProcessCtx, Registry};
use paw_types::{Attr, EventKind};

struct Counting;

thread_local! {
    static AUDIO: Cell<bool> = const { Cell::new(false) };
    static COUNT: Cell<usize> = const { Cell::new(0) };
}

fn count() {
    if AUDIO.try_with(Cell::get).unwrap_or(false) {
        let _ = COUNT.try_with(|c| c.set(c.get() + 1));
    }
}

// SAFETY: each method hands its arguments to the system allocator, which keeps the contract of
// `GlobalAlloc`.
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        count();
        // SAFETY: the caller keeps the contract of `GlobalAlloc::alloc`.
        unsafe { System.alloc(layout) }
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        count();
        // SAFETY: the caller keeps the contract of `GlobalAlloc::alloc_zeroed`.
        unsafe { System.alloc_zeroed(layout) }
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        count();
        // SAFETY: the caller keeps the contract of `GlobalAlloc::dealloc`.
        unsafe { System.dealloc(ptr, layout) }
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        count();
        // SAFETY: the caller keeps the contract of `GlobalAlloc::realloc`.
        unsafe { System.realloc(ptr, layout, new_size) }
    }
}

#[global_allocator]
static GLOBAL: Counting = Counting;

/// Run `f` as the audio thread; how many allocations and frees it made.
fn on_audio_thread(f: impl FnOnce()) -> usize {
    COUNT.with(|c| c.set(0));
    AUDIO.with(|a| a.set(true));
    f();
    AUDIO.with(|a| a.set(false));
    COUNT.with(Cell::get)
}

fn stub_dir() -> tempfile::TempDir {
    let exe = std::env::current_exe().unwrap();
    let built = exe
        .parent()
        .and_then(|deps| deps.parent())
        .unwrap()
        .join("examples/libstub_clap.so");
    assert!(built.exists(), "{} is built by `cargo test`", built.display());
    let dir = tempfile::tempdir().unwrap();
    std::fs::copy(&built, dir.path().join("stub.clap")).unwrap();
    dir
}

#[test]
fn a_clap_plugin_runs_without_allocating_on_the_audio_thread() {
    let mut registry = Registry::default();
    let stub = stub_dir();
    let mut dirs = paw_plugins::PluginDirs::default();
    paw_plugins::add_dir(&mut registry, None, &mut dirs, stub.path());
    let mut instance = registry
        .get("clap:dev.paw.stub")
        .unwrap()
        .create(48000.0, 256)
        .unwrap();
    let mut events = EventBuf::with_capacity(16);
    let (mut left, mut right) = (vec![0.0; 256], vec![0.0; 256]);
    let ctx = ProcessCtx::at(48000.0, 120.0, 4, 4, true);
    let note = |on| Event {
        frame: 0,
        kind: if on {
            EventKind::NoteOn {
                key: 60,
                vel: 1.0,
                ch: 0,
                attr: Attr {
                    kind: 0x11,
                    data: 0xA000,
                },
            }
        } else {
            EventKind::NoteOff { key: 60, ch: 0 }
        },
    };
    let mut block = |instance: &mut paw_engine::Instance, events: &mut EventBuf| {
        let mut io = Io {
            left: &mut left,
            right: &mut right,
            events,
            sidechain: None,
            outputs: &mut [],
        };
        on_audio_thread(|| {
            instance.device.set_param(0, 3.0);
            instance.device.process(&ctx, &mut io);
        })
    };

    // The first block starts the plugin processing.
    events.push(note(true));
    assert_eq!(block(&mut instance, &mut events), 0, "start and a note-on");
    events.clear();
    // The plugin tells of a state it takes on, and of a move in its window
    // inside a gesture: both are output events.
    let controller = instance.controller.as_mut().unwrap();
    controller.load_state(&7u32.to_le_bytes()).unwrap();
    assert_eq!(block(&mut instance, &mut events), 0, "a state taken on");
    let controller = instance.controller.as_mut().unwrap();
    controller.call("stub.move", b"9").unwrap();
    assert_eq!(block(&mut instance, &mut events), 0, "a gesture");
    events.push(note(false));
    assert_eq!(block(&mut instance, &mut events), 0, "a note-off");
    events.clear();
    assert_eq!(block(&mut instance, &mut events), 0, "asleep");

    let changes = instance.controller.as_mut().unwrap().take_changes();
    assert!(
        changes.iter().any(|c| c.value == 9.0 && c.edit),
        "the plugin's output events came through: {changes:?}"
    );
}
