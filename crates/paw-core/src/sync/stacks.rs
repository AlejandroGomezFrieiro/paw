//! What a MIDI clip with a modifier stack plays: the result of its stack
//! (`model/modifiers.rs`), kept by the [`ChainKey`] after each entry.
//!
//! Copies with the same notes and the same stack have the same keys, so
//! they share one result, and the compiled events of that result
//! (`clips.rs`, by the result's runs). A change of entry 3 keeps the keys
//! of entries 1 and 2: evaluation starts from the result after entry 2.

use std::sync::Arc;

use rustc_hash::FxHashMap;

use crate::model::modifiers::{ChainKey, Midi, ModKinds, Progress, evaluate};
use crate::model::{Clip, Control, Notes};

/// The results of stacks, by the key after each entry that is on.
#[derive(Default)]
pub(super) struct Results {
    /// Each result, and whether a sync asked for it since the last sweep.
    entries: FxHashMap<ChainKey, (Arc<Midi>, bool)>,
    /// How many entries there were after the last sweep.
    swept: usize,
}

impl Results {
    /// What `clip` plays of its `notes` and `controls`: `None` when no
    /// entry of its stack is on (it plays them as they are), else the
    /// result of its stack. An entry that cannot run passes its input
    /// through and puts its reason in `warnings`, once, when it runs.
    pub(super) fn played(
        &mut self,
        clip: &Clip,
        notes: &Notes,
        controls: &[Control],
        kinds: &ModKinds,
        warnings: &mut Vec<String>,
    ) -> Option<Arc<Midi>> {
        if !clip.stack.changes() {
            return None;
        }
        let source = Midi { notes: notes.clone(), controls: controls.into() };
        let first = source.source_key();
        // The key after each entry that is on, with its place.
        let mut keys = Vec::with_capacity(clip.stack.0.len());
        let mut key = first;
        for (at, entry) in clip.stack.0.iter().enumerate().filter(|(_, m)| m.is_on()) {
            key = key.then(entry);
            keys.push((at, key));
        }
        // Start after the last entry whose result is kept.
        let kept = keys.iter().rposition(|(_, k)| self.entries.contains_key(k));
        let (mut input, mut key, rest) = match kept {
            Some(i) => (self.take(&keys[i].1), keys[i].1, &keys[i + 1..]),
            None => (Arc::new(source), first, &keys[..]),
        };
        let mut skipped = Vec::new();
        for &(at, after) in rest {
            let result = match evaluate(kinds, &clip.stack.0, at..at + 1, key, Midi::clone(&input), &mut skipped) {
                Progress::Done { result, .. } => result,
                // The kernel does not run extension kinds yet: the entry
                // waits, as an entry of a kind that no one defined.
                Progress::Needs(job) => job.input,
            };
            input = Arc::new(result);
            self.entries.insert(after, (input.clone(), true));
            key = after;
        }
        for (at, why) in skipped {
            warnings.push(format!("{}: modifier {}: {why}", clip.name, at + 1));
        }
        Some(input)
    }

    /// The kept result of `key`, marked as asked for.
    fn take(&mut self, key: &ChainKey) -> Arc<Midi> {
        let (result, asked) = self.entries.get_mut(key).expect("a kept key");
        *asked = true;
        result.clone()
    }

    /// Forget the results that no sync asked for since the last sweep,
    /// once there are as many again as after it.
    pub(super) fn sweep(&mut self) {
        if self.entries.len() > 2 * self.swept + 64 {
            self.entries.retain(|_, (_, asked)| std::mem::take(asked));
            self.swept = self.entries.len();
        }
    }
}
