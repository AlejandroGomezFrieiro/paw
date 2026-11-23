//! A track's clips, kept in runs that copies of the track share.
//!
//! Every edit of a clip copies the track that holds it (the undo history
//! keeps the track as it was), and a track that kept its clips as one list
//! would copy a pointer for each clip it has: a track of 5000 clips would
//! cost 5000 for each clip moved, and as much again to compare the copy
//! with the track before it. Here the clips are kept in runs of a few dozen
//! behind `Arc`. A copy of the track copies one pointer for each run, and a
//! change copies only the run it lands in. Two states of a track compare
//! by their runs first ([`Clips::changed`]), so what an edit costs depends
//! on what it changed, not on the size of the track.
//!
//! The clips read as one list, in their order on the track: [`Clips::iter`],
//! [`Clips::get`] and indexing count across the runs.

use std::ops::{Index, IndexMut, Range};
use std::sync::Arc;

use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::Clip;

/// How many clips a run is made with. One grows to twice this before it is
/// split in two.
const RUN: usize = 32;

type Item = Arc<Clip>;
type Run = Arc<Vec<Item>>;

#[derive(Clone, Default)]
pub struct Clips {
    runs: Vec<Run>,
    /// Where each run ends: how many clips come before it and in it.
    ends: Vec<usize>,
}

/// Runs of about [`RUN`] clips each, none of them empty.
fn runs_of(items: Vec<Item>) -> Vec<Run> {
    let count = items.len().div_ceil(RUN);
    let mut left = items.len();
    let mut items = items.into_iter();
    (0..count)
        .map(|i| {
            // Evenly, so that no run is left with a few clips.
            let take = left / (count - i);
            left -= take;
            Arc::new(items.by_ref().take(take).collect())
        })
        .collect()
}

impl Clips {
    pub fn new() -> Self {
        Self::default()
    }

    fn from_runs(runs: Vec<Run>) -> Self {
        let mut clips = Self {
            ends: vec![0; runs.len()],
            runs,
        };
        clips.reindex(0);
        clips
    }

    pub fn len(&self) -> usize {
        self.ends.last().copied().unwrap_or(0)
    }

    pub fn is_empty(&self) -> bool {
        self.runs.is_empty()
    }

    /// Count the ends again from run `from` on.
    fn reindex(&mut self, from: usize) {
        let mut end = self.start(from);
        for (run, slot) in self.runs[from..].iter().zip(&mut self.ends[from..]) {
            end += run.len();
            *slot = end;
        }
    }

    /// How many clips come before run `run`.
    fn start(&self, run: usize) -> usize {
        if run == 0 { 0 } else { self.ends[run - 1] }
    }

    /// The run a clip is in, and its place there.
    fn locate(&self, index: usize) -> Option<(usize, usize)> {
        let run = self.ends.partition_point(|&end| end <= index);
        (run < self.runs.len()).then(|| (run, index - self.start(run)))
    }

    pub fn get(&self, index: usize) -> Option<&Item> {
        let (run, at) = self.locate(index)?;
        self.runs[run].get(at)
    }

    /// A clip's place in the list to change, copying its run if a copy of
    /// the track shares it.
    pub fn get_mut(&mut self, index: usize) -> Option<&mut Item> {
        let (run, at) = self.locate(index)?;
        Arc::make_mut(&mut self.runs[run]).get_mut(at)
    }

    pub fn first(&self) -> Option<&Item> {
        self.runs.first().and_then(|r| r.first())
    }

    pub fn last(&self) -> Option<&Item> {
        self.runs.last().and_then(|r| r.last())
    }

    pub fn iter(&self) -> Iter<'_> {
        Iter {
            runs: self.runs.iter(),
            front: [].iter(),
            back: [].iter(),
            left: self.len(),
        }
    }

    /// The clips in `range` of places, in order.
    pub fn range(&self, range: Range<usize>) -> std::iter::Take<Iter<'_>> {
        let count = range.end.min(self.len()).saturating_sub(range.start);
        let mut iter = self.iter();
        if range.start > 0 && count > 0 {
            iter.nth(range.start - 1);
        }
        iter.take(count)
    }

    /// Every clip to change: this copies every run a copy of the track
    /// shares, so changes to a few clips go through [`Clips::get_mut`].
    pub fn iter_mut(&mut self) -> impl Iterator<Item = &mut Item> {
        self.runs.iter_mut().flat_map(|r| Arc::make_mut(r).iter_mut())
    }

    pub fn to_vec(&self) -> Vec<Item> {
        let mut out = Vec::with_capacity(self.len());
        for run in &self.runs {
            out.extend_from_slice(run);
        }
        out
    }

    /// Put a clip at `index`, moving those from there on along.
    ///
    /// # Panics
    ///
    /// When `index` is past the end, as `Vec::insert` does.
    pub fn insert(&mut self, index: usize, clip: Item) {
        assert!(index <= self.len(), "clip {index} is past the end of {}", self.len());
        if self.runs.is_empty() {
            self.runs.push(Arc::new(vec![clip]));
            self.ends.push(1);
            return;
        }
        let (run, at) = self
            .locate(index)
            .unwrap_or((self.runs.len() - 1, self.runs[self.runs.len() - 1].len()));
        let list = Arc::make_mut(&mut self.runs[run]);
        list.insert(at, clip);
        if list.len() > 2 * RUN {
            let half = list.split_off(list.len() / 2);
            self.runs.insert(run + 1, Arc::new(half));
            self.ends.insert(run + 1, 0);
        }
        self.reindex(run);
    }

    pub fn push(&mut self, clip: Item) {
        self.insert(self.len(), clip);
    }

    /// Take out the clip at `index`.
    ///
    /// # Panics
    ///
    /// When there is no such clip, as `Vec::remove` does.
    pub fn remove(&mut self, index: usize) -> Item {
        let len = self.len();
        let (run, at) = self
            .locate(index)
            .unwrap_or_else(|| panic!("no clip {index} in {len}"));
        let list = Arc::make_mut(&mut self.runs[run]);
        let clip = list.remove(at);
        if list.is_empty() {
            self.runs.remove(run);
            self.ends.remove(run);
        }
        if run < self.runs.len() {
            self.reindex(run);
        }
        clip
    }

    pub fn extend(&mut self, clips: impl IntoIterator<Item = Item>) {
        for clip in clips {
            self.push(clip);
        }
    }

    /// Keep the clips `keep` says to, asking it of each clip once, in order.
    /// Runs it keeps whole stay shared.
    pub fn retain(&mut self, mut keep: impl FnMut(&Item) -> bool) {
        let mut changed = false;
        for run in &mut self.runs {
            let kept: Vec<bool> = run.iter().map(&mut keep).collect();
            if kept.iter().all(|k| *k) {
                continue;
            }
            changed = true;
            let mut kept = kept.into_iter();
            Arc::make_mut(run).retain(|_| kept.next().unwrap_or(true));
        }
        if changed {
            self.runs.retain(|r| !r.is_empty());
            self.ends.truncate(self.runs.len());
            self.reindex(0);
        }
    }

    /// The place of the first clip `pred` is true of.
    pub fn position(&self, pred: impl FnMut(&Item) -> bool) -> Option<usize> {
        self.iter().position(pred)
    }

    /// The places where this list and `before` (the same track in another
    /// state) may differ: every clip before `.0.start`/`.1.start` is the very
    /// same in both, and so is every clip from `.0.end` in `before` and
    /// `.1.end` in this list on. Found by the runs the two share, so it
    /// costs a step for each run and nothing for each clip.
    pub fn changed(&self, before: &Clips) -> (Range<usize>, Range<usize>) {
        let (a, b) = (&before.runs, &self.runs);
        let head = a.iter().zip(b).take_while(|(x, y)| Arc::ptr_eq(x, y)).count();
        let room = a.len().min(b.len()) - head;
        let tail = a
            .iter()
            .rev()
            .zip(b.iter().rev())
            .take(room)
            .take_while(|(x, y)| Arc::ptr_eq(x, y))
            .count();
        let from = before.start(head);
        let old_end = before.start(a.len() - tail);
        let new_end = self.start(b.len() - tail);
        (from..old_end, from..new_end)
    }

    /// Whether the two lists hold the very same clips in the same places.
    pub fn same(&self, other: &Clips) -> bool {
        let (old, new) = self.changed(other);
        old.len() == new.len()
            && other.range(old).zip(self.range(new)).all(|(a, b)| Arc::ptr_eq(a, b))
    }

    /// How many runs the list is kept in.
    pub fn runs(&self) -> usize {
        self.runs.len()
    }

    /// About how many bytes the list of runs holds, and the runs that
    /// `before` does not share.
    pub fn weight_over(&self, before: Option<&Clips>) -> usize {
        use std::mem::size_of;
        let list = self.runs.capacity() * size_of::<Run>() + self.ends.capacity() * size_of::<usize>();
        let fresh = match before {
            Some(before) => {
                let (_, new) = self.changed(before);
                new.len()
            }
            None => self.len(),
        };
        list + fresh * size_of::<Item>()
    }
}

impl From<Vec<Item>> for Clips {
    fn from(clips: Vec<Item>) -> Self {
        Self::from_runs(runs_of(clips))
    }
}

impl FromIterator<Item> for Clips {
    fn from_iter<I: IntoIterator<Item = Item>>(iter: I) -> Self {
        Self::from(iter.into_iter().collect::<Vec<_>>())
    }
}

impl Index<usize> for Clips {
    type Output = Item;
    fn index(&self, index: usize) -> &Item {
        let len = self.len();
        self.get(index)
            .unwrap_or_else(|| panic!("no clip {index} in {len}"))
    }
}

impl IndexMut<usize> for Clips {
    fn index_mut(&mut self, index: usize) -> &mut Item {
        let len = self.len();
        self.get_mut(index)
            .unwrap_or_else(|| panic!("no clip {index} in {len}"))
    }
}

impl std::fmt::Debug for Clips {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_list().entries(self.iter()).finish()
    }
}

impl Serialize for Clips {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_seq(self.iter())
    }
}

impl<'de> Deserialize<'de> for Clips {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        Vec::<Item>::deserialize(d).map(Clips::from)
    }
}

impl<'a> IntoIterator for &'a Clips {
    type Item = &'a Item;
    type IntoIter = Iter<'a>;
    fn into_iter(self) -> Iter<'a> {
        self.iter()
    }
}

impl<'a> IntoIterator for &'a mut Clips {
    type Item = &'a mut Item;
    type IntoIter = std::iter::FlatMap<
        std::slice::IterMut<'a, Run>,
        std::slice::IterMut<'a, Item>,
        fn(&'a mut Run) -> std::slice::IterMut<'a, Item>,
    >;
    /// Every clip to change, as [`Clips::iter_mut`].
    fn into_iter(self) -> Self::IntoIter {
        self.runs.iter_mut().flat_map(|r| Arc::make_mut(r).iter_mut())
    }
}

/// The clips in order, across the runs.
#[derive(Clone)]
pub struct Iter<'a> {
    runs: std::slice::Iter<'a, Run>,
    front: std::slice::Iter<'a, Item>,
    back: std::slice::Iter<'a, Item>,
    left: usize,
}

impl<'a> Iterator for Iter<'a> {
    type Item = &'a Item;

    fn next(&mut self) -> Option<&'a Item> {
        loop {
            if let Some(clip) = self.front.next() {
                self.left -= 1;
                return Some(clip);
            }
            match self.runs.next() {
                Some(run) => self.front = run.iter(),
                None => {
                    let clip = self.back.next()?;
                    self.left -= 1;
                    return Some(clip);
                }
            }
        }
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.left, Some(self.left))
    }

    fn nth(&mut self, mut n: usize) -> Option<&'a Item> {
        // Whole runs are stepped over without visiting their clips.
        while n >= self.front.len() {
            n -= self.front.len();
            self.left -= self.front.len();
            self.front = [].iter();
            match self.runs.next() {
                Some(run) => self.front = run.iter(),
                None => {
                    let skip = n.min(self.back.len());
                    self.left -= skip;
                    return self.back.nth(n).inspect(|_| self.left -= 1);
                }
            }
        }
        self.left -= n + 1;
        self.front.nth(n)
    }
}

impl DoubleEndedIterator for Iter<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        loop {
            if let Some(clip) = self.back.next_back() {
                self.left -= 1;
                return Some(clip);
            }
            match self.runs.next_back() {
                Some(run) => self.back = run.iter(),
                None => {
                    let clip = self.front.next_back()?;
                    self.left -= 1;
                    return Some(clip);
                }
            }
        }
    }
}

impl ExactSizeIterator for Iter<'_> {}

#[cfg(test)]
mod tests {
    use super::*;

    fn clip(id: u64) -> Item {
        let clip = serde_json::json!({
            "id": id, "name": "", "start": 0.0, "length": 4.0, "muted": false,
            "content": { "kind": "midi", "notes": [], "controls": [] },
        });
        Arc::new(serde_json::from_value(clip).unwrap())
    }

    fn ids(clips: &Clips) -> Vec<u64> {
        clips.iter().map(|c| c.id).collect()
    }

    fn many(count: u64) -> Clips {
        (1..=count).map(clip).collect()
    }

    #[test]
    fn clips_read_as_one_list_across_runs() {
        let clips = many(1000);
        assert!(clips.runs() > 2);
        assert_eq!(clips.len(), 1000);
        assert_eq!(clips[0].id, 1);
        assert_eq!(clips[999].id, 1000);
        assert_eq!(ids(&clips), (1..=1000).collect::<Vec<_>>());
        assert_eq!(clips.iter().next_back().unwrap().id, 1000);
        assert_eq!(clips.range(500..503).map(|c| c.id).collect::<Vec<_>>(), [501, 502, 503]);
        assert_eq!(clips.range(998..2000).count(), 2);
        assert_eq!(clips.range(0..0).count(), 0);
        assert_eq!(clips.iter().nth(700).unwrap().id, 701);
    }

    #[test]
    fn edits_act_as_on_a_vec() {
        let mut clips = many(200);
        let mut vec: Vec<u64> = (1..=200).collect();
        for (i, id) in [(0, 1001), (200, 1002), (57, 1003), (64, 1004)] {
            clips.insert(i, clip(id));
            vec.insert(i, id);
        }
        for _ in 0..80 {
            clips.insert(30, clip(2000));
            vec.insert(30, 2000);
        }
        assert_eq!(clips.remove(10).id, vec.remove(10));
        assert_eq!(clips.remove(clips.len() - 1).id, vec.pop().unwrap());
        clips.retain(|c| c.id % 3 != 0);
        vec.retain(|id| id % 3 != 0);
        assert_eq!(ids(&clips), vec);
        while !clips.is_empty() {
            clips.remove(0);
        }
        assert_eq!(clips.runs(), 0);
        clips.push(clip(5));
        assert_eq!(ids(&clips), [5]);
    }

    #[test]
    fn a_change_copies_only_its_run_and_compares_by_runs() {
        let before = many(5000);
        let mut after = before.clone();
        Arc::make_mut(&mut after[2500]).start = 4.0;
        let (old, new) = after.changed(&before);
        assert!(old.contains(&2500) && new.contains(&2500));
        assert!(old.len() <= 2 * RUN && new.len() <= 2 * RUN);
        assert!(!after.same(&before));
        assert!(before.clone().same(&before));

        let mut fewer = before.clone();
        fewer.remove(100);
        let (old, new) = fewer.changed(&before);
        assert_eq!(old.len(), new.len() + 1);
        assert!(old.len() <= 2 * RUN);

        let mut more = before.clone();
        more.push(clip(9999));
        let (old, new) = more.changed(&before);
        assert_eq!(new.len(), old.len() + 1);
        assert!(new.len() <= 2 * RUN + 1);
    }

    #[test]
    fn serialized_as_a_list() {
        let clips = many(3);
        let text = serde_json::to_string(&clips).unwrap();
        let vec: Vec<Item> = clips.to_vec();
        assert_eq!(text, serde_json::to_string(&vec).unwrap());
        let back: Clips = serde_json::from_str(&text).unwrap();
        assert_eq!(ids(&back), [1, 2, 3]);
    }
}
