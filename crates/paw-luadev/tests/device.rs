//! A Lua device run in this process, as its helper runs it.

#![expect(clippy::unwrap_used, reason = "test code: a failed unwrap is a failed test")]

use std::path::PathBuf;
use std::time::Instant;

use paw_engine::device::{Instance, Io};
use paw_engine::{Event, EventBuf, ProcessCtx};
use paw_types::{Attr, EventKind};

/// A script written to a file of its own.
fn script(name: &str, text: &str) -> PathBuf {
    let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("luadev");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(name);
    std::fs::write(&path, text).unwrap();
    path
}

/// Run one block through the device; returns what came out.
fn run(
    instance: &mut Instance,
    input: f32,
    frames: usize,
    events: &[Event],
) -> (Vec<f32>, Vec<f32>, Vec<Event>) {
    let mut left = vec![input; frames];
    let mut right = vec![input; frames];
    let mut buf = EventBuf::with_capacity(1024);
    for e in events {
        buf.push(*e);
    }
    let ctx = ProcessCtx::at(48000.0, 120.0, 4, 4, true);
    let mut io = Io {
        left: &mut left,
        right: &mut right,
        events: &mut buf,
        sidechain: None,
        outputs: &mut [],
    };
    instance.device.process(&ctx, &mut io);
    let out = buf.as_slice().to_vec();
    (left, right, out)
}

const GAIN: &str = r#"
local dsp = require("paw.dsp")
local dev = dsp.device {
  name = "Gain",
  params = {
    { key = "gain", name = "Gain", min = -60, max = 12, default = -6.0206, unit = "dB" },
    { key = "side", choices = { "Both", "Left" }, default = "Both" },
  },
}
function dev.process(b)
  local g = dsp.gain(b.params.gain)
  for i = 0, b.frames - 1 do
    b.left[i] = b.left[i] * g
    if b.params.side == 0 then b.right[i] = b.right[i] * g end
  end
end
return dev
"#;

#[test]
fn a_script_says_what_it_is() {
    let desc = paw_luadev::describe(&script("describe.lua", GAIN)).unwrap();
    assert_eq!(desc.name.as_deref(), Some("Gain"));
    assert_eq!(desc.category, paw_engine::Category::Effect);
    assert_eq!(desc.params.len(), 2);
    assert_eq!(desc.params[0].unit, "dB");
    assert_eq!(desc.params[1].choices, ["Both", "Left"]);
    assert_eq!((desc.params[1].min, desc.params[1].max), (0.0, 1.0));
}

#[test]
fn blocks_are_processed_by_the_numbers_and_follow_parameters() {
    let mut dev = paw_luadev::make(&script("gain.lua", GAIN), 48000.0, 512).unwrap();
    let (l, r, _) = run(&mut dev, 1.0, 256, &[]);
    assert!((l[0] - 0.5).abs() < 1e-4 && (r[255] - 0.5).abs() < 1e-4, "{} {}", l[0], r[255]);
    dev.device.set_param(0, 0.0);
    dev.device.set_param(1, 1.0);
    let (l, r, _) = run(&mut dev, 0.25, 256, &[]);
    assert_eq!((l[10], r[10]), (0.25, 0.25));
    dev.device.set_param(0, -6.0206);
    let (l, r, _) = run(&mut dev, 1.0, 64, &[]);
    assert!((l[0] - 0.5).abs() < 1e-4);
    assert_eq!(r[0], 1.0, "the right side left alone");
}

#[test]
fn events_are_passed_on_with_those_sent_in_order() {
    let path = script(
        "echo.lua",
        r#"
        local dsp = require("paw.dsp")
        local dev = dsp.device { midi_effect = MIDI_EFFECT }
        function dev.process(b)
          for i = b.nevents - 1, 0, -1 do
            local e = b.events[i]
            if e.type == dsp.NOTE_ON then
              b:note_on(e.frame + 5, e.key + 12, e.value / 2, e.channel, e.attr)
            elseif e.type == dsp.OTHER then
              b:pass(e, 0)
            end
          end
        end
        return dev
        "#,
    );
    // The second note carries an articulation, which the note made from it keeps.
    let pizz = Attr {
        kind: 0x11,
        data: 0xA000,
    };
    let on = |frame, key| Event {
        frame,
        kind: EventKind::NoteOn {
            key,
            vel: 0.5,
            ch: 3,
            attr: if key == 62 { pizz } else { Attr::NONE },
        },
    };
    let bend = Event {
        frame: 30,
        kind: EventKind::NoteControl {
            key: 60,
            ctl: paw_types::NoteCtl::Bend,
            value: 0.25,
            ch: 3,
        },
    };
    let text = std::fs::read_to_string(&path).unwrap();
    std::fs::write(&path, text.replace("MIDI_EFFECT", "false")).unwrap();
    let mut dev = paw_luadev::make(&path, 48000.0, 512).unwrap();
    let (_, _, out) = run(&mut dev, 0.0, 64, &[on(0, 60), on(20, 62), bend]);
    let frames: Vec<u32> = out.iter().map(|e| e.frame).collect();
    assert_eq!(frames, [0, 0, 5, 20, 25, 30], "merged in order: {out:?}");
    assert_eq!(
        out[2].kind,
        EventKind::NoteOn {
            key: 72,
            vel: 0.25,
            ch: 3,
            attr: Attr::NONE,
        }
    );
    assert_eq!(
        out[4].kind,
        EventKind::NoteOn {
            key: 74,
            vel: 0.25,
            ch: 3,
            attr: pizz,
        },
        "a note's attribute, read and sent by the script"
    );
    assert_eq!(out[1].kind, bend.kind, "an event the library does not describe, as it came");

    std::fs::write(&path, text.replace("MIDI_EFFECT", "true")).unwrap();
    let mut dev = paw_luadev::make(&path, 48000.0, 512).unwrap();
    let (_, _, out) = run(&mut dev, 0.0, 64, &[on(0, 60), on(20, 62), bend]);
    let frames: Vec<u32> = out.iter().map(|e| e.frame).collect();
    assert_eq!(frames, [0, 5, 25], "only what it sent: {out:?}");
}

#[test]
fn a_script_that_fails_stops_and_says_why() {
    let path = script(
        "fails.lua",
        r#"
        local dev = require("paw.dsp").device { category = "instrument" }
        local blocks = 0
        function dev.process(b)
          blocks = blocks + 1
          for i = 0, b.frames - 1 do b.left[i] = 1 end
          if blocks == 2 then local t = nil; return t.field end
        end
        return dev
        "#,
    );
    let mut dev = paw_luadev::make(&path, 48000.0, 512).unwrap();
    let controller = dev.controller.as_mut().unwrap();
    assert_eq!(controller.health(), None);
    assert_eq!(run(&mut dev, 0.0, 32, &[]).0[0], 1.0);
    let (l, _, _) = run(&mut dev, 0.0, 32, &[]);
    assert_eq!(l[0], 0.0, "a stopped instrument is silent");
    let why = dev.controller.as_mut().unwrap().health().unwrap();
    assert!(why.starts_with("fails.lua:7: attempt to index"), "{why}");
}

#[test]
fn calls_reach_the_script_between_blocks_and_files_are_mapped() {
    let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("luadev");
    std::fs::create_dir_all(&dir).unwrap();
    let floats = dir.join("ramp.f32");
    let ramp: Vec<u8> = (0..8).flat_map(|i| (i as f32 / 8.0).to_le_bytes()).collect();
    std::fs::write(&floats, ramp).unwrap();
    let path = script(
        "called.lua",
        r#"
        local dsp = require("paw.dsp")
        local dev = dsp.device { category = "instrument" }
        local level, table = 0, nil
        function dev.call(method, data)
          if method == "level" then level = tonumber(data) return level * 2 end
          if method == "map" then
            if table then table:close() end
            table = dsp.map(data)
            return tostring(table.n)
          end
          if method == "fail" then error("refused") end
        end
        function dev.process(b)
          for i = 0, b.frames - 1 do
            b.left[i] = level + (table and table.n > 0 and table.data[i % table.n] or 0)
          end
        end
        return dev
        "#,
    );
    let mut dev = paw_luadev::make(&path, 48000.0, 64).unwrap();
    let call = |dev: &mut Instance, method: &str, data: &[u8]| {
        dev.controller.as_mut().unwrap().call(method, data)
    };
    assert_eq!(call(&mut dev, "level", b"0.5").unwrap(), b"1");
    assert_eq!(run(&mut dev, 0.0, 16, &[]).0[3], 0.5, "the block sees what the call set");
    let floats = floats.to_string_lossy().into_owned();
    assert_eq!(call(&mut dev, "map", floats.as_bytes()).unwrap(), b"8");
    assert_eq!(run(&mut dev, 0.0, 16, &[]).0[3], 0.5 + 3.0 / 8.0, "and reads the file");
    assert!(call(&mut dev, "nothing", b"").unwrap().is_empty(), "nothing answered");
    let err = call(&mut dev, "fail", b"").unwrap_err().to_string();
    assert!(err.ends_with("refused"), "{err}");
    assert_eq!(dev.controller.as_mut().unwrap().health(), None, "a refused call does not stop it");
    let mut plain = paw_luadev::make(&script("plain.lua", GAIN), 48000.0, 64).unwrap();
    let err = call(&mut plain, "level", b"1").unwrap_err().to_string();
    assert!(err.contains("no method `level`"), "{err}");
}

#[test]
fn a_script_that_does_not_load_says_why() {
    let err = paw_luadev::make(&script("syntax.lua", "return {\n x = = 1 }"), 48000.0, 64)
        .err()
        .unwrap()
        .to_string();
    assert!(err.starts_with("syntax.lua:2:"), "{err}");
    let err = paw_luadev::describe(&script("nothing.lua", "return 5"))
        .err()
        .unwrap()
        .to_string();
    assert!(err.contains("must return its device"), "{err}");
}

#[test]
fn the_library_registers_scripts_and_sees_them_change() {
    let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("luadev-library");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("lib_gain.lua"), GAIN).unwrap();
    std::fs::write(dir.join("lib_broken.lua"), "return").unwrap();
    let mut registry = paw_engine::Registry::default();
    let found = paw_luadev::add_dir(&mut registry, &dir, 0);
    assert_eq!(found.added, ["lua:lib_gain"]);
    assert_eq!(found.errors.len(), 1);
    let info = registry.get("lua:lib_gain").unwrap().info().clone();
    assert_eq!((info.format.as_str(), info.name.as_str()), ("lua", "Gain"));
    assert!(paw_luadev::rescan(&mut registry).changed.is_empty(), "nothing changed");
    std::fs::write(dir.join("lib_gain.lua"), GAIN.replace("\"Gain\"", "\"Louder\"")).unwrap();
    assert_eq!(paw_luadev::rescan(&mut registry).changed, ["lua:lib_gain"]);
    assert_eq!(registry.get("lua:lib_gain").unwrap().info().name, "Louder");
}

/// Not a check, a number for the record: what a block costs.
#[test]
fn a_block_of_a_simple_device_is_cheap() {
    let mut dev = paw_luadev::make(&script("cost.lua", GAIN), 48000.0, 256).unwrap();
    for _ in 0..200 {
        run(&mut dev, 0.5, 256, &[]);
    }
    let started = Instant::now();
    let blocks = 2000;
    for _ in 0..blocks {
        run(&mut dev, 0.5, 256, &[]);
    }
    let each = started.elapsed() / blocks;
    eprintln!("a block of 256 frames through a gain written in Lua: {each:?}");
    // 256 frames at 48 kHz last 5.3 ms.
    assert!(each.as_micros() < 1000, "{each:?}");
}
