//! A MIDI clip's notes, kept in runs that copies of the clip share.
//!
//! The undo history keeps the project as it was after every step, and a
//! step that changed a clip keeps a copy of that clip. Kept as one list, a
//! clip of 200,000 notes would cost a copy of all of them for each note
//! changed. Here the notes are kept in runs of a few hundred behind `Arc`: a
//! copy of the clip shares every run, and a change copies only the run it
//! lands in, so a step costs about what it changed.
//!
//! The notes read as one list: [`Notes::iter`], [`Notes::get`] and indexing
//! count across the runs. Changes that touch the whole list
//! ([`Notes::retain`], [`Notes::sort_by`], [`Notes::assign`]) leave alone
//! the runs they did not change.

use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::mem::size_of;
use std::hash::{Hash, Hasher};
use std::ops::{Index, IndexMut};
use std::sync::{Arc, OnceLock};

use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::Note;

/// How many notes a run is made with. One grows to twice this before it is
/// split in two.
const RUN: usize = 256;

type Run = Arc<Vec<Note>>;

#[derive(Clone, Default)]
pub struct Notes {
    runs: Vec<Run>,
    /// Where each run ends: how many notes come before it and in it.
    ends: Vec<usize>,
    /// [`Notes::stamp`], made when first asked and forgotten by each
    /// change: every change goes through a `&mut self` method here.
    stamp: OnceLock<u64>,
}

/// Runs of about [`RUN`] notes each, none of them empty.
fn runs_of(notes: Vec<Note>) -> Vec<Run> {
    let count = notes.len().div_ceil(RUN);
    let mut left = notes.len();
    let mut notes = notes.into_iter();
    (0..count)
        .map(|i| {
            // Evenly, so that no run is left with a few notes.
            let take = left / (count - i);
            left -= take;
            Arc::new(notes.by_ref().take(take).collect())
        })
        .collect()
}

impl Notes {
    pub fn new() -> Self {
        Self::default()
    }

    fn from_runs(runs: Vec<Run>) -> Self {
        let mut notes = Self {
            ends: vec![0; runs.len()],
            runs,
            stamp: OnceLock::new(),
        };
        notes.reindex(0);
        notes
    }

    /// A number that changes whenever the notes do, so that whoever draws
    /// them knows when to ask for them again: a hash of every note, with
    /// what extensions keep on it (a lyric, a spelling), that Lua holds
    /// exactly. Made once for each change, not for each time it is asked.
    pub fn stamp(&self) -> u64 {
        *self.stamp.get_or_init(|| {
            let mut hash = std::collections::hash_map::DefaultHasher::new();
            for note in self {
                (note.start.to_bits(), note.length.to_bits()).hash(&mut hash);
                (note.pitch, note.velocity, note.attr).hash(&mut hash);
                if !note.meta.is_empty() {
                    serde_json::Value::Object(note.meta.clone()).to_string().hash(&mut hash);
                }
            }
            hash.finish() >> 11
        })
    }

    pub fn len(&self) -> usize {
        self.ends.last().copied().unwrap_or(0)
    }

    /// The runs the notes are kept in, in order: a run that two copies of
    /// a clip share is the very same `Arc`.
    pub fn runs(&self) -> &[Arc<Vec<Note>>] {
        &self.runs
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

    /// How many notes come before run `run`.
    fn start(&self, run: usize) -> usize {
        if run == 0 { 0 } else { self.ends[run - 1] }
    }

    /// The run a note is in, and its place there.
    fn locate(&self, index: usize) -> Option<(usize, usize)> {
        let run = self.ends.partition_point(|&end| end <= index);
        (run < self.runs.len()).then(|| (run, index - self.start(run)))
    }

    pub fn get(&self, index: usize) -> Option<&Note> {
        let (run, at) = self.locate(index)?;
        self.runs[run].get(at)
    }

    /// A note to change, copying its run if a copy of the clip shares it.
    pub fn get_mut(&mut self, index: usize) -> Option<&mut Note> {
        self.stamp.take();
        let (run, at) = self.locate(index)?;
        Arc::make_mut(&mut self.runs[run]).get_mut(at)
    }

    pub fn first(&self) -> Option<&Note> {
        self.runs.first().and_then(|r| r.first())
    }

    pub fn last(&self) -> Option<&Note> {
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

    /// Every note to change: this copies every run a copy of the clip shares,
    /// so changes to a few notes go through [`Notes::get_mut`] instead.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = &mut Note> {
        self.stamp.take();
        self.runs.iter_mut().flat_map(|r| Arc::make_mut(r).iter_mut())
    }

    pub fn to_vec(&self) -> Vec<Note> {
        let mut out = Vec::with_capacity(self.len());
        for run in &self.runs {
            out.extend_from_slice(run);
        }
        out
    }

    /// Put a note at `index`, moving those from there on along.
    ///
    /// # Panics
    ///
    /// When `index` is past the end, as `Vec::insert` does.
    pub fn insert(&mut self, index: usize, note: Note) {
        self.stamp.take();
        assert!(index <= self.len(), "note {index} is past the end of {}", self.len());
        if self.runs.is_empty() {
            self.runs.push(Arc::new(vec![note]));
            self.ends.push(1);
            return;
        }
        let (run, at) = self
            .locate(index)
            .unwrap_or((self.runs.len() - 1, self.runs[self.runs.len() - 1].len()));
        let list = Arc::make_mut(&mut self.runs[run]);
        list.insert(at, note);
        if list.len() > 2 * RUN {
            let half = list.split_off(list.len() / 2);
            self.runs.insert(run + 1, Arc::new(half));
            self.ends.insert(run + 1, 0);
        }
        self.reindex(run);
    }

    pub fn push(&mut self, note: Note) {
        self.insert(self.len(), note);
    }

    /// Take out the note at `index`.
    ///
    /// # Panics
    ///
    /// When there is no such note, as `Vec::remove` does.
    pub fn remove(&mut self, index: usize) -> Note {
        self.stamp.take();
        let len = self.len();
        let (run, at) = self
            .locate(index)
            .unwrap_or_else(|| panic!("no note {index} in {len}"));
        let list = Arc::make_mut(&mut self.runs[run]);
        let note = list.remove(at);
        if list.is_empty() {
            self.runs.remove(run);
            self.ends.remove(run);
        }
        if run < self.runs.len() {
            self.reindex(run);
        }
        note
    }

    pub fn extend(&mut self, notes: impl IntoIterator<Item = Note>) {
        self.stamp.take();
        let mut notes: Vec<Note> = notes.into_iter().collect();
        if notes.is_empty() {
            return;
        }
        let from = self.runs.len().saturating_sub(1);
        // Topped up while the last run has room, in runs of their own after.
        if let Some(last) = self.runs.last_mut()
            && last.len() < 2 * RUN
        {
            let room = (2 * RUN - last.len()).min(notes.len());
            Arc::make_mut(last).extend(notes.drain(..room));
        }
        let more = runs_of(notes);
        self.ends.resize(self.runs.len() + more.len(), 0);
        self.runs.extend(more);
        self.reindex(from);
    }

    /// Keep the notes `keep` says to, asking it of each note once, in order.
    pub fn retain(&mut self, mut keep: impl FnMut(&Note) -> bool) {
        self.stamp.take();
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

    /// Sort, stably, if the notes are not in order already.
    pub fn sort_by(&mut self, mut order: impl FnMut(&Note, &Note) -> Ordering) {
        if self.iter().is_sorted_by(|a, b| order(a, b) != Ordering::Greater) {
            return;
        }
        let mut all = self.to_vec();
        all.sort_by(order);
        self.assign(all);
    }

    /// The index of the first note `pred` is false of, when it is true of
    /// every note before that and of none after, as `slice::partition_point`.
    pub fn partition_point(&self, mut pred: impl FnMut(&Note) -> bool) -> usize {
        let run = self
            .runs
            .partition_point(|r| r.last().is_some_and(&mut pred));
        match self.runs.get(run) {
            Some(list) => self.start(run) + list.partition_point(pred),
            None => self.len(),
        }
    }

    /// Make the notes `notes`, keeping every run of the list before that
    /// `notes` holds whole, in its order: what a list sent back whole with a
    /// few notes changed, added or taken out shares with the list before
    /// it. The notes between the runs kept are made into runs of their own.
    pub fn assign(&mut self, notes: Vec<Note>) {
        self.stamp.take();
        let old = std::mem::take(&mut self.runs);
        let holds = |at: usize, run: &Run| notes.get(at..at + run.len()) == Some(&run[..]);
        // Where in `notes` each run kept begins, looking for each a little
        // past where the one before ended (a note added or taken out moves
        // the rest along), and else by where its first note is.
        let mut kept: Vec<(usize, &Run)> = Vec::new();
        let mut at = 0;
        let mut index: Option<HashMap<(u64, u8, u64), usize>> = None;
        for run in &old {
            let first = &run[0];
            let found = (at..notes.len().min(at + 2 * RUN + 1))
                .find(|&i| notes[i] == *first && holds(i, run))
                .or_else(|| {
                    let index = index.get_or_insert_with(|| {
                        let mut index = HashMap::with_capacity(notes.len());
                        for (i, n) in notes.iter().enumerate().rev() {
                            index.insert((n.start.to_bits(), n.pitch, n.id), i);
                        }
                        index
                    });
                    index
                        .get(&(first.start.to_bits(), first.pitch, first.id))
                        .copied()
                        .filter(|&i| i >= at && holds(i, run))
                });
            if let Some(i) = found {
                kept.push((i, run));
                at = i + run.len();
            }
        }
        let mut runs: Vec<Run> = Vec::with_capacity(old.len() + 2);
        let mut notes = notes.into_iter();
        let mut done = 0;
        // Notes between the runs kept top up the run before them while it
        // has room, as `extend` does: notes added one at a time would
        // otherwise each make a run of their own.
        let between = |runs: &mut Vec<Run>, mut new: Vec<Note>| {
            if let Some(last) = runs.last_mut()
                && last.len() < 2 * RUN
                && !new.is_empty()
            {
                let room = (2 * RUN - last.len()).min(new.len());
                Arc::make_mut(last).extend(new.drain(..room));
            }
            runs.extend(runs_of(new));
        };
        for (i, run) in kept {
            between(&mut runs, notes.by_ref().take(i - done).collect());
            notes.by_ref().take(run.len()).for_each(drop);
            runs.push(run.clone());
            done = i + run.len();
        }
        between(&mut runs, notes.collect());
        *self = Self::from_runs(runs);
    }

    /// The places of the notes that have no id, or the id of a note before
    /// them: the ones [`super::name_notes`] names. Asked of every clip an
    /// edit changed, so it is quick for the many notes that are named.
    pub fn unnamed(&self) -> Vec<usize> {
        let mut out = Vec::new();
        let highest = self.iter().map(|n| n.id).max().unwrap_or(0);
        // Ids are given one after another, so they mostly fit a bit for
        // each id up to the highest; a hash set takes the rest.
        if highest <= 8 * self.len() as u64 + 4096 {
            let mut seen = vec![0u64; (highest >> 6) as usize + 1];
            for (i, n) in self.iter().enumerate() {
                let (word, bit) = ((n.id >> 6) as usize, 1 << (n.id & 63));
                if n.id == 0 || seen[word] & bit != 0 {
                    out.push(i);
                }
                seen[word] |= bit;
            }
        } else {
            let mut seen = HashSet::with_capacity(self.len());
            out.extend(
                self.iter()
                    .enumerate()
                    .filter(|(_, n)| n.id == 0 || !seen.insert(n.id))
                    .map(|(i, _)| i),
            );
        }
        out
    }

    /// About how many bytes these notes hold that `before` does not share
    /// with them: the runs that are not also `before`'s, and the list of runs.
    pub fn weight_over(&self, before: Option<&Notes>) -> usize {
        // The runs at both ends that are the very same are found in step;
        // only those between are looked for among the runs of `before`.
        let old: &[Run] = before.map_or(&[], |b| &b.runs);
        let head = old.iter().zip(&self.runs).take_while(|(a, b)| Arc::ptr_eq(a, b)).count();
        let room = old.len().min(self.runs.len()) - head;
        let tail = old
            .iter()
            .rev()
            .zip(self.runs.iter().rev())
            .take(room)
            .take_while(|(a, b)| Arc::ptr_eq(a, b))
            .count();
        let shared: HashSet<*const Vec<Note>> =
            old[head..old.len() - tail].iter().map(Arc::as_ptr).collect();
        let list = self.runs.capacity() * size_of::<Run>() + self.ends.capacity() * size_of::<usize>();
        list + self.runs[head..self.runs.len() - tail]
            .iter()
            .filter(|r| !shared.contains(&Arc::as_ptr(r)))
            .map(|r| {
                // The two counts `Arc` keeps beside the list.
                2 * size_of::<usize>()
                    + size_of::<Vec<Note>>()
                    + r.capacity() * size_of::<Note>()
                    + r.iter().map(|n| n.meta.len() * 64).sum::<usize>()
            })
            .sum::<usize>()
    }
}

impl From<Vec<Note>> for Notes {
    fn from(notes: Vec<Note>) -> Self {
        Self::from_runs(runs_of(notes))
    }
}

impl FromIterator<Note> for Notes {
    fn from_iter<I: IntoIterator<Item = Note>>(iter: I) -> Self {
        Self::from(iter.into_iter().collect::<Vec<_>>())
    }
}

impl Index<usize> for Notes {
    type Output = Note;
    fn index(&self, index: usize) -> &Note {
        let len = self.len();
        self.get(index)
            .unwrap_or_else(|| panic!("no note {index} in {len}"))
    }
}

impl IndexMut<usize> for Notes {
    fn index_mut(&mut self, index: usize) -> &mut Note {
        let len = self.len();
        self.get_mut(index)
            .unwrap_or_else(|| panic!("no note {index} in {len}"))
    }
}

impl PartialEq for Notes {
    fn eq(&self, other: &Self) -> bool {
        self.len() == other.len() && self.iter().eq(other.iter())
    }
}

impl std::fmt::Debug for Notes {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_list().entries(self.iter()).finish()
    }
}

impl Serialize for Notes {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_seq(self.iter())
    }
}

impl<'de> Deserialize<'de> for Notes {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        Vec::<Note>::deserialize(d).map(Notes::from)
    }
}

impl<'a> IntoIterator for &'a Notes {
    type Item = &'a Note;
    type IntoIter = Iter<'a>;
    fn into_iter(self) -> Iter<'a> {
        self.iter()
    }
}

/// The notes in order, across the runs.
#[derive(Clone)]
pub struct Iter<'a> {
    runs: std::slice::Iter<'a, Run>,
    front: std::slice::Iter<'a, Note>,
    back: std::slice::Iter<'a, Note>,
    left: usize,
}

impl<'a> Iterator for Iter<'a> {
    type Item = &'a Note;

    fn next(&mut self) -> Option<&'a Note> {
        loop {
            if let Some(note) = self.front.next() {
                self.left -= 1;
                return Some(note);
            }
            match self.runs.next() {
                Some(run) => self.front = run.iter(),
                None => {
                    let note = self.back.next()?;
                    self.left -= 1;
                    return Some(note);
                }
            }
        }
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.left, Some(self.left))
    }

    fn nth(&mut self, mut n: usize) -> Option<&'a Note> {
        // Whole runs are stepped over without visiting their notes.
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
            if let Some(note) = self.back.next_back() {
                self.left -= 1;
                return Some(note);
            }
            match self.runs.next_back() {
                Some(run) => self.back = run.iter(),
                None => {
                    let note = self.front.next_back()?;
                    self.left -= 1;
                    return Some(note);
                }
            }
        }
    }
}

impl ExactSizeIterator for Iter<'_> {}

#[cfg(test)]
mod tests {
    use super::*;

    fn note(start: f64) -> Note {
        Note {
            start,
            length: 0.25,
            pitch: 60,
            velocity: 100,
            meta: Default::default(),
            id: 0,
            attr: None,
        }
    }

    fn starts(notes: &Notes) -> Vec<f64> {
        notes.iter().map(|n| n.start).collect()
    }

    fn many(count: usize) -> Notes {
        (0..count).map(|i| note(i as f64)).collect()
    }

    /// The runs two lists hold the very same of.
    fn shared(a: &Notes, b: &Notes) -> usize {
        a.runs
            .iter()
            .filter(|r| b.runs.iter().any(|o| Arc::ptr_eq(r, o)))
            .count()
    }

    #[test]
    fn stamp_follows_each_change_and_equal_notes_share_it() {
        let mut notes = many(600);
        let first = notes.stamp();
        let copy = notes.clone();
        notes[300].pitch = 61;
        assert_ne!(notes.stamp(), first, "a note changed in place");
        notes[300].pitch = 60;
        assert_eq!(notes.stamp(), first, "the same notes again");
        notes.push(note(700.0));
        assert_ne!(notes.stamp(), first, "a note added");
        notes.retain(|n| n.start < 700.0);
        assert_eq!(notes.stamp(), first, "and taken out");
        assert_eq!(copy.stamp(), first, "a copy made before keeps its own");
    }

    #[test]
    fn notes_read_as_one_list_across_runs() {
        let notes = many(1000);
        assert!(notes.runs.len() > 2);
        assert_eq!(notes.len(), 1000);
        assert_eq!(notes[0].start, 0.0);
        assert_eq!(notes[999].start, 999.0);
        assert_eq!(notes.get(1000), None);
        assert_eq!(starts(&notes), (0..1000).map(|i| i as f64).collect::<Vec<_>>());
        let back: Vec<f64> = notes.iter().rev().map(|n| n.start).collect();
        assert_eq!(back[0], 999.0);
        assert_eq!(back.len(), 1000);
        assert_eq!(notes.iter().len(), 1000);
        for n in [0, 1, 255, 256, 300, 700, 999] {
            assert_eq!(notes.iter().nth(n).map(|n| n.start), Some(n as f64), "nth {n}");
        }
        assert_eq!(notes.iter().nth(1000), None);
        let mut it = notes.iter();
        it.nth(500);
        assert_eq!(it.len(), 499);
        // Both ends at once meet in the middle.
        let mut it = notes.iter();
        let (mut front, mut back) = (0, 0);
        while it.next().is_some() {
            front += 1;
            if it.next_back().is_some() {
                back += 1;
            }
        }
        assert_eq!(front + back, 1000);
        assert_eq!(notes.partition_point(|n| n.start < 600.5), 601);
        assert_eq!(notes.partition_point(|_| true), 1000);
        assert_eq!(notes.partition_point(|_| false), 0);
    }

    #[test]
    fn a_change_copies_only_the_run_it_lands_in() {
        let before = many(10_000);
        let runs = before.runs.len();
        let mut after = before.clone();
        assert_eq!(shared(&after, &before), runs, "a copy shares every run");
        after[5000].velocity = 1;
        assert_eq!(shared(&after, &before), runs - 1);
        assert!(after.weight_over(Some(&before)) < 30_000, "{}", after.weight_over(Some(&before)));
        assert!(before.weight_over(None) > 10_000 * size_of::<Note>());

        let mut after = before.clone();
        after.insert(5000, note(4999.5));
        after.remove(20);
        assert_eq!(shared(&after, &before), runs - 2);
        assert_eq!(after.len(), 10_000);
        assert_eq!(after[4999].start, 4999.5);
        assert_eq!((after[19].start, after[20].start), (19.0, 21.0));
    }

    #[test]
    fn runs_split_as_they_grow_and_go_when_empty() {
        let mut notes = Notes::new();
        for i in 0..2000 {
            notes.insert(notes.len() / 2, note(i as f64));
        }
        assert_eq!(notes.len(), 2000);
        assert!(notes.runs.iter().all(|r| r.len() <= 2 * RUN));
        for _ in 0..2000 {
            notes.remove(notes.len() / 3);
        }
        assert!(notes.is_empty());
        assert!(notes.runs.is_empty() && notes.ends.is_empty());
        notes.push(note(1.0));
        notes.extend((2..600).map(|i| note(i as f64)));
        assert_eq!(starts(&notes), (1..600).map(|i| i as f64).collect::<Vec<_>>());
        assert!(notes.runs.iter().all(|r| !r.is_empty() && r.len() <= 2 * RUN));
    }

    #[test]
    fn whole_list_changes_keep_the_runs_they_leave_alone() {
        let before = many(10_000);
        let runs = before.runs.len();

        let mut after = before.clone();
        let mut at = 0;
        // A predicate that counts, as callers' do: asked once per note.
        after.retain(|_| {
            at += 1;
            at != 7001
        });
        assert_eq!(after.len(), 9_999);
        assert_eq!(after[7000].start, 7001.0);
        assert_eq!(shared(&after, &before), runs - 1);

        let mut after = before.clone();
        after.sort_by(|a, b| a.start.total_cmp(&b.start));
        assert_eq!(shared(&after, &before), runs, "in order already: nothing copied");
        after[3000].start = 3000.5 + 2.0;
        after.sort_by(|a, b| a.start.total_cmp(&b.start));
        assert_eq!(after[3002].start, 3002.5);
        assert!(shared(&after, &before) >= runs - 2);

        let mut list = before.to_vec();
        list[9000].pitch = 61;
        list.insert(100, note(99.5));
        let mut after = before.clone();
        after.assign(list.clone());
        assert_eq!(after.to_vec(), list);
        assert!(shared(&after, &before) >= runs - 3, "{} of {runs}", shared(&after, &before));
        // Many notes added in one place: the runs after them are found too.
        let mut list = before.to_vec();
        list.splice(3000..3000, (0..2000).map(|i| note(2999.0 + i as f64 / 4000.0)));
        let mut after = before.clone();
        after.assign(list.clone());
        assert_eq!(after.to_vec(), list);
        assert!(shared(&after, &before) >= runs - 2, "{} of {runs}", shared(&after, &before));
        after.assign(Vec::new());
        assert!(after.is_empty());
    }

    #[test]
    fn notes_added_one_at_a_time_through_the_whole_list_fill_runs() {
        let mut notes = Notes::new();
        for i in 0..2000 {
            let mut list = notes.to_vec();
            list.push(note(i as f64));
            notes.assign(list);
        }
        assert_eq!(starts(&notes), (0..2000).map(|i| i as f64).collect::<Vec<_>>());
        assert!(notes.runs.len() <= 2000 / RUN + 1, "{} runs", notes.runs.len());
    }

    #[test]
    fn unnamed_notes_are_found_with_ids_dense_or_sparse() {
        let mut notes = many(1000);
        assert_eq!(notes.unnamed().len(), 1000, "none has an id");
        for (i, n) in notes.iter_mut().enumerate() {
            n.id = i as u64 + 1;
        }
        assert!(notes.unnamed().is_empty());
        notes[500].id = 3;
        notes[700].id = 0;
        assert_eq!(notes.unnamed(), [500, 700]);
        for (i, n) in notes.iter_mut().enumerate() {
            n.id = (i as u64 + 1) << 40;
        }
        assert!(notes.unnamed().is_empty());
        notes[900].id = notes[10].id;
        assert_eq!(notes.unnamed(), [900]);
    }

    #[test]
    fn notes_are_written_and_read_as_a_plain_list() {
        let notes = many(600);
        let text = serde_json::to_string(&notes).unwrap();
        assert!(text.starts_with("[{"));
        let back: Notes = serde_json::from_str(&text).unwrap();
        assert_eq!(back, notes);
        let plain: Vec<Note> = serde_json::from_str(&text).unwrap();
        assert_eq!(plain, notes.to_vec());
    }
}
