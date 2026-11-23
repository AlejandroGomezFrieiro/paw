//! A processor runs the plan of its chain: devices in series, and splits
//! whose branches are summed again. A monitored stereo input on track 1
//! is the source, so that each test knows what goes into the chain.

use paw_engine::plan::{Branch, Node, Split, Splitter, Tree, compile};
use paw_engine::{
    Device, DeviceSlot, Engine, EngineHandle, GraphPlan, Io, Msg, ProcessCtx, SchedEntry, Schedule, TrackRt, TrackSlot,
};

use crate::common::{SR, send};

/// Multiplies its input by a gain.
struct Scale(f32);

impl Device for Scale {
    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        for s in io.left.iter_mut().chain(io.right.iter_mut()) {
            *s *= self.0;
        }
    }
    fn set_param(&mut self, _index: u32, _value: f32) {}
}

/// Puts out its input a fixed number of frames late, as a device that
/// looks ahead does.
struct Late {
    line: Vec<[f32; 2]>,
    at: usize,
}

impl Late {
    fn new(frames: usize) -> Box<Self> {
        Box::new(Self { line: vec![[0.0; 2]; frames], at: 0 })
    }
}

impl Device for Late {
    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            let [old_l, old_r] = std::mem::replace(&mut self.line[self.at], [*l, *r]);
            (*l, *r) = (old_l, old_r);
            self.at = (self.at + 1) % self.line.len();
        }
    }
    fn set_param(&mut self, _index: u32, _value: f32) {}
}

const BLOCK: usize = 128;
const TRACK: TrackSlot = TrackSlot(1);

/// An engine that plays track 1 into the master, with `devices` in device
/// slots 0, 1, ... and the stereo input monitored on track 1.
struct Rig {
    engine: Engine,
    handle: EngineHandle,
    frame: usize,
}

impl Rig {
    fn new(devices: Vec<Box<dyn Device>>) -> Self {
        let (mut engine, mut handle) = Engine::new(SR);
        send(&mut handle, Msg::InsertTrack { slot: TRACK, track: TrackRt::new() });
        for (i, device) in devices.into_iter().enumerate() {
            send(&mut handle, Msg::InsertDevice { slot: DeviceSlot(i as u32), device });
        }
        let entries =
            vec![SchedEntry::new(TRACK, TrackSlot::MASTER), SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE)];
        send(&mut handle, Msg::SetSchedule(Box::new(Schedule::new(entries, 0))));
        send(&mut handle, Msg::SetInput { track: TRACK, first: 0, channels: 2, monitor: true, armed: false });
        send(&mut handle, Msg::Play);
        engine.pump();
        Self { engine, handle, frame: 0 }
    }

    fn set(&mut self, plan: Box<GraphPlan>) {
        send(&mut self.handle, Msg::SetGraph { slot: TRACK.into(), plan });
    }

    /// The next `frames` frames of the master, with `input` of each frame
    /// (counted from the start) on the input.
    fn run(&mut self, frames: usize, input: impl Fn(usize) -> [f32; 2]) -> Vec<[f32; 2]> {
        let mut out = Vec::with_capacity(frames);
        let (mut left, mut right) = (vec![0.0; BLOCK], vec![0.0; BLOCK]);
        for _ in 0..frames / BLOCK {
            let interleaved: Vec<f32> = (self.frame..self.frame + BLOCK).flat_map(&input).collect();
            self.engine.process_input(&interleaved, 2, &mut left, &mut right);
            out.extend(left.iter().zip(&right).map(|(l, r)| [*l, *r]));
            self.frame += BLOCK;
        }
        self.handle.collect_garbage();
        out
    }
}

fn device(slot: u32) -> Node {
    Node::Device { slot: DeviceSlot(slot), latency: 0 }
}

fn branch(tag: u64, nodes: Vec<Node>) -> Branch {
    Branch { tag, nodes, gain: 1.0, pan: 0.0, mute: false, solo: false, zone: None }
}

fn split(splitter: Splitter, branches: Vec<Branch>) -> Node {
    Node::Split(Box::new(Split { tag: 100, splitter, branches, mix: 1.0, gain: 1.0 }))
}

fn plan(nodes: Vec<Node>) -> Box<GraphPlan> {
    compile(&Tree { nodes }, SR as f32)
}

/// Two signals that differ in each channel and frame.
fn music(frame: usize) -> [f32; 2] {
    let t = frame as f32 / SR as f32;
    let l =
        0.5 * (2.0 * std::f32::consts::PI * 220.0 * t).sin() + 0.2 * (2.0 * std::f32::consts::PI * 3100.0 * t).sin();
    let r = 0.4 * (2.0 * std::f32::consts::PI * 330.0 * t).sin() - 0.3 * (2.0 * std::f32::consts::PI * 70.0 * t).cos();
    [l, r]
}

/// The master's output of `plan` over `frames`, with `devices`.
fn render(
    devices: Vec<Box<dyn Device>>,
    plan: Box<GraphPlan>,
    frames: usize,
    input: impl Fn(usize) -> [f32; 2],
) -> Vec<[f32; 2]> {
    let mut rig = Rig::new(devices);
    rig.set(plan);
    rig.run(frames, input)
}

fn scales() -> Vec<Box<dyn Device>> {
    vec![Box::new(Scale(0.5)), Box::new(Scale(-1.5))]
}

/// The largest difference of two renders, sample by sample.
fn largest_difference(a: &[[f32; 2]], b: &[[f32; 2]]) -> f32 {
    a.iter().zip(b).flat_map(|(x, y)| [(x[0] - y[0]).abs(), (x[1] - y[1]).abs()]).fold(0.0, f32::max)
}

#[test]
fn a_chain_in_a_split_of_one_plain_branch_renders_the_bits_of_the_chain_in_series() {
    let series = render(scales(), GraphPlan::serial(&[DeviceSlot(0), DeviceSlot(1)]), 4096, music);
    let rack = plan(vec![device(0), split(Splitter::Layer, vec![branch(1, vec![device(1)])])]);
    // A split that is not plain takes the long way: a copy into a branch
    // buffer, a merge and an output stage, each at unity.
    let keys = plan(vec![device(0), split(Splitter::Keys, vec![branch(1, vec![device(1)])])]);
    assert!(series.iter().any(|f| f[0].abs() > 0.1), "something sounds");
    for (name, plan) in [("a rack", rack), ("a split of one branch", keys)] {
        let other = render(scales(), plan, 4096, music);
        assert_eq!(other, series, "{name} and the chain in series");
    }
}

#[test]
fn empty_splits_give_back_their_input_and_a_layer_sums_its_branches() {
    let reference = render(vec![], GraphPlan::serial(&[]), 4096, music);
    let empty = |splitter, count: u64| plan(vec![split(splitter, (1..=count).map(|t| branch(t, vec![])).collect())]);
    // The bits of a mid/side round trip can differ in the last place.
    let cases = [
        ("a left/right split", empty(Splitter::LeftRight, 2), 1.0, 0.0),
        ("a mid/side split", empty(Splitter::MidSide, 2), 1.0, 1e-6),
        ("a layer of three equal branches", empty(Splitter::Layer, 3), 3.0, 1e-6),
    ];
    for (name, plan, gain, limit) in cases {
        let got = render(vec![], plan, 4096, music);
        let want: Vec<[f32; 2]> = reference.iter().map(|[l, r]| [l * gain, r * gain]).collect();
        let difference = largest_difference(&got, &want);
        assert!(difference <= limit, "{name}: off by {difference}");
    }
}

#[test]
fn the_bands_of_an_empty_band_split_sum_flat() {
    let bands = || plan(vec![split(Splitter::Band(vec![120.0, 2000.0]), (1..=3).map(|t| branch(t, vec![])).collect())]);
    let frames = 48000;
    // The level of the last quarter, after the filters have settled.
    let level = |out: &[[f32; 2]]| {
        let tail = &out[frames * 3 / 4..];
        (tail.iter().map(|f| f[0] * f[0]).sum::<f32>() / tail.len() as f32).sqrt()
    };
    for freq in [40.0f32, 120.0, 500.0, 2000.0, 9000.0] {
        let sine = |frame: usize| {
            let v = 0.5 * (2.0 * std::f32::consts::PI * freq * frame as f32 / SR as f32).sin();
            [v, v]
        };
        let through = level(&render(vec![], bands(), frames, sine));
        let straight = level(&render(vec![], GraphPlan::serial(&[]), frames, sine));
        let db = 20.0 * (through / straight).log10();
        // A hundredth of a dB: far under what anyone hears.
        assert!(db.abs() < 0.01, "{freq} Hz is {db} dB off");
    }
}

/// One impulse on frame 1000.
fn impulse(frame: usize) -> [f32; 2] {
    if frame == 1000 { [1.0, 1.0] } else { [0.0, 0.0] }
}

#[test]
fn a_late_branch_is_waited_for_so_that_the_branches_and_the_dry_signal_meet() {
    let late = |mix: f32| {
        let mut slow = branch(1, vec![Node::Device { slot: DeviceSlot(0), latency: 64 }]);
        slow.gain = 0.5;
        let mut fast = branch(2, vec![]);
        fast.gain = 0.5;
        let mut s = Split { tag: 100, splitter: Splitter::Layer, branches: vec![slow, fast], mix, gain: 1.0 };
        if mix < 1.0 {
            // One branch, so that the dry and the wet signal are each half.
            s.branches.truncate(1);
            s.branches[0].gain = 1.0;
        }
        compile(&Tree { nodes: vec![Node::Split(Box::new(s))] }, SR as f32)
    };
    for (name, plan) in [("two branches", late(1.0)), ("a branch and the dry signal", late(0.5))] {
        assert_eq!(plan.latency(), 64, "{name}: the latency of the chain");
        let out = render(vec![Late::new(64)], plan, 2048, impulse);
        let heard: Vec<usize> = (0..out.len()).filter(|&i| out[i][0].abs() > 1e-6).collect();
        assert_eq!(heard, [1064], "{name}: one impulse, as late as the slowest path");
        // The track's fader in the middle is a hair from unity.
        assert!((out[1064][0] - 1.0).abs() < 1e-5, "{name}: both halves arrive together: {}", out[1064][0]);
    }
}

/// A steady input of 1 on both channels.
fn steady(_frame: usize) -> [f32; 2] {
    [1.0, 1.0]
}

#[test]
fn a_plan_of_another_shape_fades_out_and_in_while_the_song_plays() {
    let mut rig = Rig::new(vec![Box::new(Scale(1.0)), Box::new(Scale(2.0))]);
    rig.set(GraphPlan::serial(&[DeviceSlot(0)]));
    let before = rig.run(1024, steady);
    rig.set(GraphPlan::serial(&[DeviceSlot(1)]));
    let after = rig.run(1024, steady);
    let level = before.last().unwrap()[0];
    // 5 ms out and 5 ms in, at 48 kHz: 240 frames each way.
    let fade = 240;
    let lowest = after[..2 * fade].iter().map(|f| f[0]).fold(f32::MAX, f32::min);
    assert!(lowest < 0.01 * level, "the old chain fades out to {lowest}");
    let largest_step = after.windows(2).map(|w| (w[1][0] - w[0][0]).abs()).fold(0.0, f32::max);
    assert!(largest_step <= 2.0 * level / fade as f32 * 1.01, "no step larger than the fade's: {largest_step}");
    // The swap waits for the end of the block where the old chain is out.
    let full = after[4 * BLOCK..].iter().all(|f| (f[0] - 2.0 * level).abs() < 1e-5);
    assert!(full, "the new chain plays in full after the fade");
}

#[test]
fn a_plan_of_the_same_shape_takes_over_without_a_fade() {
    let layer = |gain: f32| {
        let mut first = branch(1, vec![device(0)]);
        first.gain = gain;
        plan(vec![split(Splitter::Layer, vec![first, branch(2, vec![])])])
    };
    let mut rig = Rig::new(vec![Box::new(Scale(1.0))]);
    rig.set(layer(1.0));
    let before = rig.run(1024, steady);
    rig.set(layer(2.0));
    let after = rig.run(1024, steady);
    let level = before.last().unwrap()[0] / 2.0;
    let lowest = after.iter().map(|f| f[0]).fold(f32::MAX, f32::min);
    assert!(lowest >= 2.0 * level - 1e-5, "it does not dip: {lowest}");
    assert!((after[BLOCK][0] - 3.0 * level).abs() < 1e-5, "the new gain after one block");
}

#[test]
fn the_engine_measures_each_device_and_branch() {
    let tree = plan(vec![split(Splitter::Layer, vec![branch(7, vec![device(0)]), branch(8, vec![])])]);
    let meters = tree.meters().clone();
    let mut rig = Rig::new(vec![Box::new(Scale(0.25))]);
    rig.set(tree);
    rig.run(1024, steady);
    let shared = rig.engine.shared();
    assert_eq!(shared.device_peak(DeviceSlot(0)), 0.25, "the peak after the device");
    assert!(shared.device_time(DeviceSlot(0)) > 0, "the time the device ran is counted");
    assert_eq!(meters.peak(7), Some((0.25, 0.25)), "the branch with the device");
    assert_eq!(meters.peak(8), Some((1.0, 1.0)), "the empty branch");
    assert_eq!(meters.peak(100), Some((1.25, 1.25)), "the split after its merge");
}
