//! A CLAP plugin of the tests' own (examples/stub_clap.rs), found in a
//! directory added while the program runs, given notes with attributes as
//! MIDI 2.0, asked what it calls its keys, and told when a render is offline.

use paw_engine::{Event, EventBuf, Instance, Io, ProcessCtx, Registry};
use paw_plugins::PluginDirs;
use paw_types::{Attr, EventKind};
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
fn a_plugin_in_an_added_directory_takes_the_attribute_and_names_its_keys() {
    let dir = stub_dir();
    let mut registry = Registry::default();
    let kind = "clap:dev.paw.stub";
    assert!(registry.get(kind).is_none());
    // No usual folders: only the added one is searched.
    let mut dirs = PluginDirs::default();
    let (kinds, notes) = paw_plugins::add_dir(&mut registry, None, &mut dirs, dir.path());
    assert_eq!(
        kinds,
        [kind],
        "found only after the directory was added ({notes:?})"
    );
    assert!(registry.get(kind).is_some());

    let mut instance = registry.get(kind).unwrap().create(48000.0, 256).unwrap();
    let mut events = EventBuf::with_capacity(16);
    let attr = Attr {
        kind: 0x11,
        data: 0xA000,
    };
    events.push(Event {
        frame: 0,
        kind: EventKind::NoteOn {
            key: 60,
            vel: 1.0,
            ch: 0,
            attr,
        },
    });
    let (mut left, mut right) = (vec![0.0; 256], vec![0.0; 256]);
    let ctx = ProcessCtx::at(48000.0, 120.0, 4, 4, true);
    instance.device.process(
        &ctx,
        &mut Io {
            left: &mut left,
            right: &mut right,
            events: &mut events,
            sidechain: None,
            outputs: &mut [],
        },
    );
    // The plugin prefers MIDI 2.0: the note-on came as a packet with the
    // attribute's type in its first word and its data in its second.
    // SAFETY: the stub plugin is a library of this workspace that runs no code when it loads.
    let lib = unsafe { libloading::Library::new(dir.path().join("stub.clap")).unwrap() };
    let last: libloading::Symbol<unsafe extern "C" fn(*mut u32) -> u32> =
        // SAFETY: `stub_clap_last` has this signature in the stub plugin.
        unsafe { lib.get(b"stub_clap_last\0").unwrap() };
    let mut words = [0u32; 2];
    // SAFETY: `words` is two words, as `stub_clap_last` needs.
    assert_eq!(unsafe { last(words.as_mut_ptr()) }, 1);
    assert_eq!(words, [0x4090_3c11, 0xffff_a000]);
    assert_eq!(
        left[100],
        0x11 as f32 / 256.0,
        "it plays the articulation it was given"
    );
    assert_eq!(right[100], 0xA as f32 / 16.0);
    assert!(!instance.device.resting(), "a plugin with a note sounding works");

    // Let go of the note: the plugin says it sleeps, and may be left to.
    events.clear();
    events.push(Event {
        frame: 0,
        kind: EventKind::NoteOff { key: 60, ch: 0 },
    });
    let mut io = Io {
        left: &mut left,
        right: &mut right,
        events: &mut events,
        sidechain: None,
        outputs: &mut [],
    };
    instance.device.process(&ctx, &mut io);
    assert!(instance.device.resting(), "the plugin said it sleeps");
    instance.device.set_param(0, 0.5);
    assert!(!instance.device.resting(), "a parameter to deliver wakes it");
    instance.device.process(&ctx, &mut io);
    assert!(instance.device.resting(), "asleep again");

    // A state it takes on only in its next block wakes it: asleep, it
    // would never take it.
    let state: libloading::Symbol<extern "C" fn() -> u32> =
        // SAFETY: `stub_clap_state` has this signature in the stub plugin.
        unsafe { lib.get(b"stub_clap_state\0").unwrap() };
    let controller = instance.controller.as_mut().unwrap();
    controller.load_state(&7u32.to_le_bytes()).unwrap();
    assert_eq!(state(), 0, "not taken on yet");
    assert!(!instance.device.resting(), "a state to take on wakes it");
    instance.device.process(&ctx, &mut io);
    assert_eq!(state(), 7, "taken on in the block it was woken for");
    assert_eq!(
        instance.controller.as_mut().unwrap().save_state().unwrap(),
        Some(7u32.to_le_bytes().to_vec())
    );
    assert!(instance.device.resting(), "and asleep again");

    let names = instance
        .controller
        .as_mut()
        .unwrap()
        .call("note-names", &[])
        .unwrap();
    let names: serde_json::Value = serde_json::from_slice(&names).unwrap();
    assert_eq!(
        names,
        serde_json::json!({ "24": "Sustain", "26": "Staccato" })
    );
}

/// The modes that the stub tells (`stub.render`): the render mode of its
/// first block, and the render mode that it has now.
fn render_modes(instance: &mut Instance) -> String {
    let controller = instance.controller.as_mut().unwrap();
    String::from_utf8(controller.call("stub.render", &[]).unwrap()).unwrap()
}

#[test]
fn a_plugin_set_offline_renders_offline_until_it_is_set_back() {
    let dir = stub_dir();
    let mut registry = Registry::default();
    let mut dirs = PluginDirs::default();
    paw_plugins::add_dir(&mut registry, None, &mut dirs, dir.path());
    let mut instance = registry
        .get("clap:dev.paw.stub")
        .unwrap()
        .create(48000.0, 256)
        .unwrap();
    assert_eq!(render_modes(&mut instance), "no-block none");

    instance.controller.as_mut().unwrap().set_offline(true);
    let mut events = EventBuf::with_capacity(4);
    let (mut left, mut right) = (vec![0.0; 256], vec![0.0; 256]);
    let ctx = ProcessCtx::at(48000.0, 120.0, 4, 4, true);
    instance.device.process(
        &ctx,
        &mut Io {
            left: &mut left,
            right: &mut right,
            events: &mut events,
            sidechain: None,
            outputs: &mut [],
        },
    );
    assert_eq!(
        render_modes(&mut instance),
        "offline offline",
        "clap.render set(OFFLINE) came before the first block"
    );

    instance.controller.as_mut().unwrap().set_offline(false);
    assert_eq!(render_modes(&mut instance), "offline realtime");
}
