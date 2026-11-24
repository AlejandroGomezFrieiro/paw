//! A part that plays clips of its own can also be the output of other
//! parts: what they send in is summed with its clips before its devices.
//! (A nest's "chain mode" places a nest part's sound into its host part,
//! which has clips of its own: it depends on this.)
#![cfg_attr(test, expect(clippy::cast_possible_truncation, reason = "debt: pay down"))]

use paw_engine::GraphPlan;
use paw_engine::{
    ClipSet, DeviceSlot, Engine, MAX_BLOCK, Msg, Registry, SchedEntry, Schedule, PartRt, PartSlot,
};

use crate::common::{SR, send};

const BLOCKS: usize = 200;

/// Part 1 (a synth) goes into part 2, and part 2 (a synth, then a
/// utility at `gain` dB) into the master. Each part holds one note when
/// asked, at different keys. Returns the master's left channel.
fn render(feed_note: bool, host_note: bool, gain: f32) -> Vec<f32> {
    let (mut engine, mut handle) = Engine::new(SR);
    let registry = Registry::with_builtins();
    let make = |name: &str| {
        registry
            .get(name)
            .unwrap()
            .create(SR as f32, MAX_BLOCK)
            .unwrap()
            .device
    };
    let clips_of = |note: Option<u8>| {
        let mut clips = ClipSet::default();
        if let Some(key) = note {
            clips.push_note(0.0, 64.0, key, 0.8);
        }
        clips.finish();
        Box::new(clips)
    };
    let feed = clips_of(feed_note.then_some(60));
    let host = clips_of(host_note.then_some(67));
    for msg in [
        Msg::InsertPart { slot: PartSlot(1), part: PartRt::new() },
        Msg::InsertPart { slot: PartSlot(2), part: PartRt::new() },
        Msg::InsertDevice { slot: DeviceSlot(0), device: make("synth") },
        Msg::InsertDevice { slot: DeviceSlot(1), device: make("synth") },
        Msg::InsertDevice { slot: DeviceSlot(2), device: make("utility") },
        Msg::SetParam { device: DeviceSlot(2), param: 0, value: gain },
        Msg::SetGraph { slot: PartSlot(1).into(), plan: GraphPlan::serial(&[DeviceSlot(0)]) },
        Msg::SetGraph { slot: PartSlot(2).into(), plan: GraphPlan::serial(&[DeviceSlot(1), DeviceSlot(2)]) },
        Msg::SetClips { part: PartSlot(1), clips: feed },
        Msg::SetClips { part: PartSlot(2), clips: host },
        Msg::SetSchedule(Box::new(Schedule::new(
            vec![
                SchedEntry::new(PartSlot(1), PartSlot(2)),
                SchedEntry::new(PartSlot(2), PartSlot::MASTER),
                SchedEntry::new(PartSlot::MASTER, PartSlot::NONE),
            ],
            0,
        ))),
        Msg::Seek(0.0),
        Msg::Play,
    ] {
        send(&mut handle, msg);
    }
    let (mut l, mut r) = (vec![0.0; 256], vec![0.0; 256]);
    let mut out = Vec::with_capacity(BLOCKS * 256);
    for _ in 0..BLOCKS {
        engine.process(&mut l, &mut r);
        out.extend_from_slice(&l);
    }
    out
}

fn peak(x: &[f32]) -> f32 {
    x.iter().fold(0f32, |m, s| m.max(s.abs()))
}

fn worst(a: &[f32], b: impl Iterator<Item = f32>) -> f32 {
    a.iter().zip(b).map(|(x, y)| (x - y).abs()).fold(0f32, f32::max)
}

#[test]
fn a_bus_with_clips_sums_its_input_with_its_clips_before_its_devices() {
    let both = render(true, true, -6.0);
    let fed = render(true, false, -6.0);
    let own = render(false, true, -6.0);
    assert!(peak(&fed) > 0.01 && peak(&own) > 0.01, "each part sounds alone");
    // The host's devices are linear here (a synth adds, a utility scales):
    // both together are the sum of each alone.
    let sum = fed.iter().zip(&own).map(|(a, b)| a + b);
    assert!(worst(&both, sum) < 1e-5, "the input and the clips are summed");
    // The input goes through the host's devices: the utility's -6 dB.
    let unity = render(true, false, 0.0);
    let scaled = unity.iter().map(|s| s * 0.501_187);
    assert!(worst(&fed, scaled) < 1e-5, "the input passes through the chain");
}
