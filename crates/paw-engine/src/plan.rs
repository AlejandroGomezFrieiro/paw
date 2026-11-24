//! A plan of a chain: the flat list of operations that the audio thread
//! runs for one processor slot, made from a tree of splits and branches.
//!
//! The main thread describes a chain as a [`Tree`] of device slots,
//! splits and branches, and [`compile`] turns it into a [`GraphPlan`]. The
//! plan owns everything its operations need: its work buffers and delay
//! lines in one `Box<[f32]>`, an event list for each branch that needs
//! its own, the state of its crossover filters, and the gains of its
//! branches. The audio thread runs the operations in order. It never
//! allocates for a plan, and a plan that is replaced goes back to the main
//! thread to be freed.
//!
//! Buffer 0 ([`Buf::SLOT`]) is the slot's own buffer: the input of the
//! chain and its output. A chain in series compiles to one run of each
//! device on buffer 0, so it does the same work as a list of devices.
//!
//! The kinds of split here are those that the engine plays. The main
//! thread resolves the kind of each split of the model before it builds the
//! tree: a kind that the engine does not play becomes its first branch in
//! series.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::float_cmp, reason = "debt: pay down")]

mod crossover;

use std::sync::Arc;
use std::sync::atomic::Ordering::Relaxed;

use atomic_float::AtomicF32;

use crate::engine::MAX_BLOCK;
use crate::event::EventBuf;
use crate::slot::DeviceSlot;

pub(crate) use crossover::{Allpass, Crossover};

/// The longest delay that lines up the branches of a split, in frames.
pub const MAX_PLAN_DELAY: u32 = 1 << 17;

/// How many events an event list of a branch holds, as the slot's own does.
pub const EVENTS: usize = 1024;

/// A chain as the main thread describes it: nodes in series.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Tree {
    pub nodes: Vec<Node>,
}

/// One node of a branch.
#[derive(Clone, Debug, PartialEq)]
pub enum Node {
    /// A device, and the frames by which its output is behind its input.
    Device {
        slot: DeviceSlot,
        latency: u32,
    },
    Split(Box<Split>),
}

/// A split: its input goes into each branch, and the branches are summed.
#[derive(Clone, Debug, PartialEq)]
pub struct Split {
    /// What the main thread knows the split by: the key of its meter.
    pub tag: u64,
    pub splitter: Splitter,
    pub branches: Vec<Branch>,
    /// The share of the merged branches in the output, 0 (dry) to 1 (wet).
    pub mix: f32,
    /// The gain after the merge, linear.
    pub gain: f32,
}

/// One path through a split: nodes in series.
#[derive(Clone, Debug, PartialEq)]
pub struct Branch {
    /// What the main thread knows the branch by: the key of its meter.
    pub tag: u64,
    pub nodes: Vec<Node>,
    /// Linear.
    pub gain: f32,
    /// -1 (left) to 1 (right).
    pub pan: f32,
    pub mute: bool,
    pub solo: bool,
    /// The notes (a [`Splitter::Keys`] split) or velocities (a
    /// [`Splitter::Velocities`] split) that the branch hears, both ends in
    /// it; `None` for all.
    pub zone: Option<(u8, u8)>,
}

/// How a split divides its input between its branches.
#[derive(Clone, Debug, PartialEq)]
pub enum Splitter {
    /// Each branch gets a copy of the input.
    Layer,
    /// Each branch gets a band of frequencies: Linkwitz-Riley crossovers of
    /// 24 dB an octave at these frequencies in Hz, low to high, one fewer
    /// than the branches. The bands sum flat.
    Band(Vec<f32>),
    /// The first branch gets the mid signal, the second the side signal.
    MidSide,
    /// The first branch gets the left channel, the second the right.
    LeftRight,
    /// Each branch gets a copy of the input and the notes of its key zone.
    Keys,
    /// Each branch gets a copy of the input and the notes of its velocity
    /// zone.
    Velocities,
}

/// A stereo buffer of a plan.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Buf(u16);

impl Buf {
    /// The slot's own buffer: the input of the chain and its output.
    pub const SLOT: Self = Self(0);

    pub(crate) fn index(self) -> usize {
        self.0 as usize
    }
}

/// An event list of a plan. 0 is the slot's own.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Ev(u16);

impl Ev {
    pub(crate) fn index(self) -> usize {
        self.0 as usize
    }
}

/// Which notes a copy of an event list keeps.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Filter {
    All,
    Keys(u8, u8),
    Velocities(u8, u8),
}

/// What part of a stereo signal goes into a branch, or how a branch goes
/// back into the merge.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Part {
    Stereo,
    Mid,
    Side,
    Left,
    Right,
}

/// One operation of a plan. The values that can change without a change
/// of the shape (gains, crossover frequencies) are not here, so two plans
/// with equal operations have the same shape.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Op {
    /// Run a device on a buffer with an event list.
    Run {
        device: DeviceSlot,
        buf: Buf,
        events: Ev,
    },
    Clear {
        buf: Buf,
    },
    Copy {
        from: Buf,
        to: Buf,
    },
    /// Copy an event list, with only the notes of `filter`.
    Events {
        from: Ev,
        to: Ev,
        filter: Filter,
    },
    /// The part of `from` that a branch takes, in both channels of `to`.
    Take {
        from: Buf,
        to: Buf,
        part: Part,
    },
    /// Crossover `xover`: `low` gets the low band of `rest`, and `rest`
    /// keeps the high band.
    Band {
        rest: Buf,
        low: Buf,
        xover: u16,
    },
    /// An allpass filter that lines up a low band with a crossover above it.
    Allpass {
        buf: Buf,
        filter: u16,
    },
    /// Hold a buffer back by its delay line `ring`.
    Delay {
        buf: Buf,
        ring: u16,
    },
    /// Add `from` into `to` with the gains `gain`, as `part`.
    Merge {
        from: Buf,
        to: Buf,
        gain: u16,
        part: Part,
    },
    /// `to` (the dry signal) with the gain `dry_gain`, plus `wet` with the
    /// gain `wet_gain`: the mix and the gain of a split.
    Out {
        wet: Buf,
        to: Buf,
        wet_gain: u16,
        dry_gain: u16,
    },
    /// Measure the peak of a buffer into a meter.
    Meter {
        buf: Buf,
        meter: u16,
    },
}

/// A gain for each channel that moves from where the last block left it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Gain {
    pub(crate) target: [f32; 2],
    pub(crate) applied: [f32; 2],
}

/// A delay line in the plan's buffer, after the work buffers: `len`
/// frames for each channel at `start`, left then right.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Ring {
    pub(crate) start: usize,
    pub(crate) len: usize,
    pub(crate) at: usize,
}

/// The peaks of the splits and branches of a plan, which the audio thread
/// writes and the main thread reads. Each meter has the tag of its node.
#[derive(Debug, Default)]
pub struct PlanMeters {
    tags: Box<[u64]>,
    peaks: Box<[[AtomicF32; 2]]>,
}

impl PlanMeters {
    /// The peak `(left, right)` of the split or branch `tag`, linear,
    /// falling as a part's meter falls.
    pub fn peak(&self, tag: u64) -> Option<(f32, f32)> {
        let at = self.tags.iter().position(|t| *t == tag)?;
        let [l, r] = &self.peaks[at];
        Some((l.load(Relaxed), r.load(Relaxed)))
    }

    pub(crate) fn store(&self, meter: u16, peak: [f32; 2], fall: f32) {
        if let Some(m) = self.peaks.get(meter as usize) {
            for (ch, p) in peak.into_iter().enumerate() {
                let held = m[ch].load(Relaxed) * fall;
                m[ch].store(p.max(held), Relaxed);
            }
        }
    }
}

/// A compiled chain: what the audio thread runs for one processor slot.
/// Only [`compile`] makes one.
pub struct GraphPlan {
    pub(crate) ops: Box<[Op]>,
    /// The work buffers (from buffer 1, `2 * MAX_BLOCK` each), then the
    /// delay lines.
    pub(crate) arena: Box<[f32]>,
    /// How many work buffers are at the start of `arena`.
    pub(crate) bufs: usize,
    /// The event lists from 1.
    pub(crate) events: Box<[EventBuf]>,
    pub(crate) crossovers: Box<[Crossover]>,
    pub(crate) allpasses: Box<[Allpass]>,
    pub(crate) gains: Box<[Gain]>,
    pub(crate) rings: Box<[Ring]>,
    pub(crate) meters: Arc<PlanMeters>,
    latency: u32,
}

impl GraphPlan {
    /// The devices in `slots` in series.
    pub fn serial(slots: &[DeviceSlot]) -> Box<Self> {
        compile(&Tree::serial(slots), SERIAL_RATE)
    }

    /// The frames by which the output of the chain is behind its input.
    pub fn latency(&self) -> u32 {
        self.latency
    }

    /// The meters of the plan's splits and branches.
    pub fn meters(&self) -> &Arc<PlanMeters> {
        &self.meters
    }

    /// How many stereo buffers the plan holds besides the slot's own.
    pub fn buffers(&self) -> usize {
        self.bufs
    }

    /// True when `other` has the same operations and delay lines: then the
    /// state of one goes on in the other.
    pub fn same_shape(&self, other: &GraphPlan) -> bool {
        self.ops == other.ops
            && self.rings.len() == other.rings.len()
            && self.rings.iter().zip(other.rings.iter()).all(|(a, b)| a.len == b.len)
    }

    /// Go on from where `old`, of the same shape, is: its filters, its
    /// delay lines and the gains it applied. The new values become the
    /// targets the gains move to. On the audio thread: no allocation.
    pub(crate) fn adopt(&mut self, old: &mut GraphPlan) {
        debug_assert!(self.same_shape(old));
        for (new, old) in self.crossovers.iter_mut().zip(old.crossovers.iter()) {
            new.adopt(old);
        }
        for (new, old) in self.allpasses.iter_mut().zip(old.allpasses.iter()) {
            new.adopt(old);
        }
        for (new, old) in self.gains.iter_mut().zip(old.gains.iter()) {
            new.applied = old.applied;
        }
        let lines = self.bufs * 2 * MAX_BLOCK;
        self.arena[lines..].copy_from_slice(&old.arena[lines..]);
        for (new, old) in self.rings.iter_mut().zip(old.rings.iter()) {
            new.at = old.at;
        }
        // The meters go on in the new plan's table.
        for (new, old) in self.meters.peaks.iter().zip(old.meters.peaks.iter()) {
            for ch in 0..2 {
                new[ch].store(old[ch].load(Relaxed), Relaxed);
            }
        }
    }
}

/// The rate a plan with no crossover is compiled at: it uses none.
const SERIAL_RATE: f32 = 48000.0;

impl Tree {
    /// The devices in `slots` in series, with no latency.
    pub fn serial(slots: &[DeviceSlot]) -> Self {
        Self { nodes: slots.iter().map(|&slot| Node::Device { slot, latency: 0 }).collect() }
    }

    /// The frames by which the output of the chain is behind its input:
    /// the latencies in series added, and the longest branch of a split.
    pub fn latency(&self) -> u32 {
        series_latency(&self.nodes)
    }
}

fn series_latency(nodes: &[Node]) -> u32 {
    nodes
        .iter()
        .map(|node| match node {
            Node::Device { latency, .. } => (*latency).min(MAX_PLAN_DELAY),
            Node::Split(split) => split.latency(),
        })
        .fold(0u32, u32::saturating_add)
        .min(MAX_PLAN_DELAY)
}

impl Split {
    fn latency(&self) -> u32 {
        self.branches.iter().map(|b| series_latency(&b.nodes)).max().unwrap_or(0)
    }

    /// True when the split changes nothing around its one branch: a rack
    /// at unity, which runs as its nodes in series.
    fn is_plain(&self) -> bool {
        self.splitter == Splitter::Layer
            && self.mix == 1.0
            && self.gain == 1.0
            && matches!(self.branches.as_slice(), [b] if b.gain == 1.0 && b.pan == 0.0 && !b.mute)
    }
}

impl Branch {
    /// The gain of each channel: equal-power pan, unity in the middle.
    fn gains(&self, silenced: bool) -> [f32; 2] {
        if self.mute || silenced {
            return [0.0, 0.0];
        }
        if self.pan == 0.0 {
            return [self.gain, self.gain];
        }
        let angle = (self.pan.clamp(-1.0, 1.0) + 1.0) * std::f32::consts::FRAC_PI_4;
        let scale = self.gain * std::f32::consts::SQRT_2;
        [scale * angle.cos(), scale * angle.sin()]
    }
}

/// Make the plan of `tree` at `sample_rate`. On the main thread: it
/// allocates everything the plan will need.
pub fn compile(tree: &Tree, sample_rate: f32) -> Box<GraphPlan> {
    let mut c = Compiler { sample_rate, ..Compiler::default() };
    c.series(&tree.nodes, Buf::SLOT, Ev(0));
    let mut lines = 0;
    let rings: Vec<Ring> = c
        .rings
        .iter()
        .map(|&len| {
            let ring = Ring { start: lines, len, at: 0 };
            lines += 2 * len;
            ring
        })
        .collect();
    let arena_len = c.max_bufs * 2 * MAX_BLOCK + lines;
    let meters = PlanMeters {
        peaks: c.meters.iter().map(|_| [AtomicF32::new(0.0), AtomicF32::new(0.0)]).collect(),
        tags: c.meters.into(),
    };
    Box::new(GraphPlan {
        ops: c.ops.into(),
        arena: vec![0.0; arena_len].into(),
        bufs: c.max_bufs,
        events: (0..c.max_events).map(|_| EventBuf::with_capacity(EVENTS)).collect(),
        crossovers: c.crossovers.into(),
        allpasses: c.allpasses.into(),
        gains: c.gains.into(),
        rings: rings.into(),
        meters: Arc::new(meters),
        latency: tree.latency(),
    })
}

/// What [`compile`] keeps while it walks the tree. Buffers and event lists
/// are taken as a stack: a split takes its own, the splits in its branches
/// take theirs above them, and each gives them back when it is done. So
/// the plan needs as many buffers as the deepest path through the tree.
#[derive(Default)]
struct Compiler {
    sample_rate: f32,
    ops: Vec<Op>,
    bufs: usize,
    max_bufs: usize,
    events: usize,
    max_events: usize,
    crossovers: Vec<Crossover>,
    allpasses: Vec<Allpass>,
    gains: Vec<Gain>,
    /// The length of each delay line.
    rings: Vec<usize>,
    /// The tag of each meter.
    meters: Vec<u64>,
}

impl Compiler {
    fn buf(&mut self) -> Buf {
        self.bufs += 1;
        self.max_bufs = self.max_bufs.max(self.bufs);
        Buf(self.bufs as u16)
    }

    fn events(&mut self) -> Ev {
        self.events += 1;
        self.max_events = self.max_events.max(self.events);
        Ev(self.events as u16)
    }

    fn gain(&mut self, target: [f32; 2]) -> u16 {
        self.gains.push(Gain { target, applied: target });
        (self.gains.len() - 1) as u16
    }

    fn meter(&mut self, tag: u64, buf: Buf) {
        let meter = self.meters.len() as u16;
        self.meters.push(tag);
        self.ops.push(Op::Meter { buf, meter });
    }

    fn delay(&mut self, buf: Buf, frames: u32) {
        if frames > 0 {
            self.rings.push(frames.min(MAX_PLAN_DELAY) as usize);
            let ring = (self.rings.len() - 1) as u16;
            self.ops.push(Op::Delay { buf, ring });
        }
    }

    fn series(&mut self, nodes: &[Node], buf: Buf, events: Ev) {
        for node in nodes {
            match node {
                Node::Device { slot, .. } => self.ops.push(Op::Run { device: *slot, buf, events }),
                Node::Split(split) => self.split(split, buf, events),
            }
        }
    }

    fn split(&mut self, split: &Split, buf: Buf, events: Ev) {
        if split.branches.is_empty() {
            // Nothing to split into: the signal goes on as it is.
            return;
        }
        if split.is_plain() {
            let branch = &split.branches[0];
            self.series(&branch.nodes, buf, events);
            self.meter(branch.tag, buf);
            self.meter(split.tag, buf);
            return;
        }
        let (mark_bufs, mark_events) = (self.bufs, self.events);
        let latency = split.latency();
        let wet = self.buf();
        let branch_buf = self.buf();
        self.ops.push(Op::Clear { buf: wet });
        // The dry signal waits for the branches; with no latency it is the
        // input itself, still in its buffer at the end.
        let dry = (split.mix < 1.0 && latency > 0).then(|| {
            let dry = self.buf();
            self.ops.push(Op::Copy { from: buf, to: dry });
            self.delay(dry, latency);
            dry
        });
        let rest = match &split.splitter {
            Splitter::Band(_) => {
                let rest = self.buf();
                self.ops.push(Op::Copy { from: buf, to: rest });
                Some(rest)
            }
            _ => None,
        };
        let solo = split.branches.iter().any(|b| b.solo);
        let count = split.branches.len();
        for (i, branch) in split.branches.iter().enumerate() {
            let part = self.source(split, i, buf, branch_buf, rest);
            let branch_events = self.branch_events(split, branch, count, events);
            self.series(&branch.nodes, branch_buf, branch_events);
            self.delay(branch_buf, latency - series_latency(&branch.nodes));
            self.meter(branch.tag, branch_buf);
            let gain = self.gain(branch.gains(solo && !branch.solo));
            self.ops.push(Op::Merge { from: branch_buf, to: wet, gain, part });
            if branch_events != events {
                self.events -= 1;
            }
        }
        let wet_gain = self.gain([split.gain * split.mix; 2]);
        let dry_gain = self.gain([1.0 - split.mix; 2]);
        if let Some(dry) = dry {
            self.ops.push(Op::Copy { from: dry, to: buf });
        }
        self.ops.push(Op::Out { wet, to: buf, wet_gain, dry_gain });
        self.meter(split.tag, buf);
        self.bufs = mark_bufs;
        self.events = mark_events;
    }

    /// Put the input of branch `i` into `to`: how the branch goes back
    /// into the merge.
    fn source(&mut self, split: &Split, i: usize, from: Buf, to: Buf, rest: Option<Buf>) -> Part {
        match &split.splitter {
            Splitter::Layer | Splitter::Keys | Splitter::Velocities => {
                self.ops.push(Op::Copy { from, to });
                Part::Stereo
            }
            Splitter::MidSide => {
                let part = if i == 0 { Part::Mid } else { Part::Side };
                self.ops.push(Op::Take { from, to, part });
                part
            }
            Splitter::LeftRight => {
                let part = if i == 0 { Part::Left } else { Part::Right };
                self.ops.push(Op::Take { from, to, part });
                part
            }
            Splitter::Band(xovers) => {
                let rest = rest.expect("a band split has a buffer for the rest");
                let bands = split.branches.len();
                if i + 1 < bands {
                    let freq = band_edge(xovers, i, bands);
                    self.crossovers.push(Crossover::new(freq, self.sample_rate));
                    let xover = (self.crossovers.len() - 1) as u16;
                    self.ops.push(Op::Band { rest, low: to, xover });
                    // The bands above split again; this band goes through
                    // the same phase as they do, so that all sum flat.
                    for j in i + 1..bands - 1 {
                        let freq = band_edge(xovers, j, bands);
                        self.allpasses.push(Allpass::new(freq, self.sample_rate));
                        let filter = (self.allpasses.len() - 1) as u16;
                        self.ops.push(Op::Allpass { buf: to, filter });
                    }
                } else {
                    self.ops.push(Op::Copy { from: rest, to });
                }
                Part::Stereo
            }
        }
    }

    /// The event list of a branch: a copy of the split's, filtered by the
    /// branch's zone, when the branch could change it for the others.
    fn branch_events(&mut self, split: &Split, branch: &Branch, count: usize, from: Ev) -> Ev {
        let filter = match (&split.splitter, branch.zone) {
            (Splitter::Keys, Some((low, high))) => Filter::Keys(low, high),
            (Splitter::Velocities, Some((low, high))) => Filter::Velocities(low, high),
            _ if count > 1 => Filter::All,
            _ => return from,
        };
        let to = self.events();
        self.ops.push(Op::Events { from, to, filter });
        to
    }
}

/// The crossover `i` of a band split of `bands` bands: the frequency the
/// main thread gave, or one spread over the range of music.
fn band_edge(xovers: &[f32], i: usize, bands: usize) -> f32 {
    xovers.get(i).copied().unwrap_or_else(|| {
        // Even steps on a log scale from 80 Hz to 10 kHz.
        let steps = (bands.max(2) - 1) as f32;
        80.0 * 125.0f32.powf(i as f32 / steps.max(1.0))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(slot: u32) -> Node {
        Node::Device { slot: DeviceSlot(slot), latency: 0 }
    }

    fn branch(tag: u64, nodes: Vec<Node>) -> Branch {
        Branch { tag, nodes, gain: 1.0, pan: 0.0, mute: false, solo: false, zone: None }
    }

    fn split(splitter: Splitter, branches: Vec<Branch>) -> Node {
        Node::Split(Box::new(Split { tag: 1, splitter, branches, mix: 1.0, gain: 1.0 }))
    }

    #[test]
    fn a_chain_in_series_runs_each_device_on_the_slot_buffer() {
        let plan = GraphPlan::serial(&[DeviceSlot(3), DeviceSlot(1)]);
        let ev = Ev(0);
        assert_eq!(
            &*plan.ops,
            [
                Op::Run { device: DeviceSlot(3), buf: Buf::SLOT, events: ev },
                Op::Run { device: DeviceSlot(1), buf: Buf::SLOT, events: ev },
            ]
        );
        assert_eq!(plan.buffers(), 0, "no buffer besides the slot's");
        assert!(plan.arena.is_empty(), "nothing allocated for buffers");
    }

    #[test]
    fn splits_side_by_side_share_their_buffers_and_nested_ones_take_more() {
        let layer = |inner: Vec<Node>| split(Splitter::Layer, vec![branch(2, inner), branch(3, vec![device(9)])]);
        let side_by_side = compile(&Tree { nodes: vec![layer(vec![device(1)]), layer(vec![device(2)])] }, 48000.0);
        assert_eq!(side_by_side.buffers(), 2, "two splits in series reuse one pair");
        let nested = compile(&Tree { nodes: vec![layer(vec![layer(vec![device(1)])])] }, 48000.0);
        assert_eq!(nested.buffers(), 4, "a split in a branch takes a pair above its parent's");
    }

    #[test]
    fn values_do_not_change_the_shape_and_branches_do() {
        let band = |xover: f32, gain: f32| {
            let mut b = vec![branch(2, vec![device(1)]), branch(3, vec![])];
            b[0].gain = gain;
            compile(&Tree { nodes: vec![split(Splitter::Band(vec![xover]), b)] }, 48000.0)
        };
        assert!(band(200.0, 1.0).same_shape(&band(900.0, 0.5)), "other values, the same shape");
        let three = compile(
            &Tree {
                nodes: vec![split(Splitter::Layer, vec![branch(2, vec![]), branch(3, vec![]), branch(4, vec![])])],
            },
            48000.0,
        );
        assert!(!band(200.0, 1.0).same_shape(&three), "another split is another shape");
    }
}
