//! The order parts are processed in, and how it is shared between threads.

use std::collections::HashMap;

use crate::slot::PartSlot;

use super::part::{Delay, KeyRt, OutRt, SendRt};

pub struct SchedEntry {
    pub slot: PartSlot,
    /// Where the part's output goes. [`PartSlot::NONE`] for the master part.
    pub output: PartSlot,
    /// How long the output waits for slower parts that feed the same place.
    pub delay: Delay,
    pub sends: Vec<SendRt>,
    /// Devices elsewhere that listen to this part.
    pub keys: Vec<KeyRt>,
    /// Further output pairs of the part's devices, and where they go.
    pub outs: Vec<OutRt>,
}

impl SchedEntry {
    pub fn new(slot: PartSlot, output: PartSlot) -> Self {
        Self {
            slot,
            output,
            delay: Delay::default(),
            sends: Vec::new(),
            keys: Vec::new(),
            outs: Vec::new(),
        }
    }

    /// Whether something is taken from the part before its fader, which
    /// then waits until that has been done.
    pub(super) fn taps_pre(&self) -> bool {
        self.sends.iter().any(|send| send.pre) || self.keys.iter().any(|key| key.pre)
    }
}

/// Processing order: every part appears after all parts that feed it, and
/// the master part is last.
///
/// The entries are kept in groups: the parts nothing feeds, then those fed
/// only by the first group, and so on. The parts of a group do not depend on
/// each other, so they can be processed side by side; what they send on is
/// then added up in the order of the entries, on one thread, so that the
/// sums, and with them the output, do not depend on how many threads ran.
#[derive(Default)]
pub struct Schedule {
    pub entries: Vec<SchedEntry>,
    /// Frames by which the output is behind the transport, because of
    /// devices that report latency.
    pub latency: u32,
    /// Where each group ends in `entries`.
    pub(super) groups: Vec<usize>,
    /// What each group takes to process, in nanoseconds of work over the
    /// last few blocks, and whether it is shared out: a group is shared
    /// between threads only when there is enough work in it.
    pub(super) costs: Vec<(u64, bool)>,
    /// The most work a block has taken while playing, falling slowly: so
    /// that the first blocks after a stop, or after a silence that devices
    /// slept through, are shared out as the song needs, before it is
    /// measured again.
    pub(super) peak: u64,
}

impl Schedule {
    /// `entries` in an order where every part comes after all that feed it.
    pub fn new(entries: Vec<SchedEntry>, latency: u32) -> Self {
        // How many groups each part has to wait for.
        let mut waits: HashMap<PartSlot, usize> = HashMap::new();
        let mut keyed: Vec<(usize, SchedEntry)> = entries
            .into_iter()
            .map(|entry| {
                let group = waits.get(&entry.slot).copied().unwrap_or(0);
                let targets = std::iter::once(entry.output)
                    .chain(entry.sends.iter().map(|s| s.target))
                    .chain(entry.keys.iter().map(|k| k.part))
                    .chain(entry.outs.iter().map(|o| o.target));
                for target in targets {
                    let wait = waits.entry(target).or_default();
                    *wait = (*wait).max(group + 1);
                }
                // The master is last whatever feeds it.
                (
                    if entry.slot == PartSlot::MASTER {
                        usize::MAX
                    } else {
                        group
                    },
                    entry,
                )
            })
            .collect();
        keyed.sort_by_key(|(group, _)| *group);
        let mut groups = Vec::new();
        for (index, pair) in keyed.windows(2).enumerate() {
            if pair[0].0 != pair[1].0 {
                groups.push(index + 1);
            }
        }
        groups.push(keyed.len());
        Self {
            entries: keyed.into_iter().map(|(_, entry)| entry).collect(),
            latency,
            costs: vec![(0, false); groups.len()],
            peak: 0,
            groups,
        }
    }

    /// Whether the group `group`, entries `first..last`, is worth sharing
    /// between threads. Waking other threads costs more than a little work:
    /// a group is shared out when it took long enough on one thread, and
    /// kept shared out until it takes much less.
    pub(super) fn worth_sharing(&self, group: usize, first: usize, last: usize) -> bool {
        let (cost, shared) = self.costs.get(group).copied().unwrap_or((0, false));
        last > first + 1
            && if shared {
                cost >= SHARE_NS / 2
            } else {
                cost >= SHARE_NS
            }
    }

    /// Whether a group after `group`, which ends at entry `last`, is worth
    /// sharing between threads.
    pub(super) fn worth_sharing_after(&self, group: usize, last: usize) -> bool {
        let mut first = last;
        for later in group + 1..self.groups.len() {
            let end = self.groups[later];
            if self.worth_sharing(later, first, end) {
                return true;
            }
            first = end;
        }
        false
    }

    /// The work of all the groups, as last measured.
    pub(super) fn cost(&self) -> u64 {
        self.costs.iter().map(|c| c.0).sum()
    }

    /// Keep what a group's parts took, whichever threads did them, without
    /// the waiting: smoothed, so that one block the thread was held up in
    /// does not change how the next is done.
    pub(super) fn note_cost(&mut self, group: usize, spent: u64, shared: bool) {
        if let Some(slot) = self.costs.get_mut(group) {
            *slot = ((slot.0 * 3 + spent) / 4, shared);
        }
    }

    /// After a block played: the most work a block has taken, which falls
    /// by half in about 7000 blocks, a minute at 256 frames.
    pub(super) fn hold_peak(&mut self) {
        self.peak = self.cost().max(self.peak - self.peak / 10_000);
    }

    /// Where the group that starts at entry `first` ends.
    pub(super) fn group_end(&self, first: usize) -> usize {
        let at = self.groups.partition_point(|end| *end <= first);
        self.groups
            .get(at)
            .copied()
            .unwrap_or(self.entries.len())
            .clamp(first + 1, self.entries.len().max(first + 1))
    }
}

/// Nanoseconds of work in a group of parts, on one thread, above which it
/// is shared between threads: less is done sooner on one than it takes to
/// wake the others.
pub(super) const SHARE_NS: u64 = 60_000;
