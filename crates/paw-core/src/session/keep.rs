//! Letting go of decoded audio no clip needs any more.
//!
//! Decoded files are kept so that clips sharing a file, and undo, do not
//! decode it again. A file that neither the project nor any undo step
//! refers to is dropped, so that a long session opening project after
//! project does not hold every file it ever played.

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Arc;

use super::Session;
use crate::model::{ClipContent, Project, Part};

/// Checkpoints between looks at what is still referred to.
const EVERY: u32 = 64;

impl Session {
    /// Count a checkpoint, and every so often drop unneeded audio.
    pub(super) fn trim_audio_now_and_then(&mut self) {
        self.trims = self.trims.wrapping_add(1);
        if self.trims.is_multiple_of(EVERY) {
            self.trim_audio();
        }
    }

    /// Drop decoded audio that no clip in the project or its undo history uses.
    pub(crate) fn trim_audio(&mut self) {
        // A running render was built from what is in the cache: leave it be
        // until the render is over (its engine holds what it plays anyway).
        // Nothing to let go (a project of MIDI alone): looking through every
        // step of the history for files would find nothing to keep.
        if self.rendering() || self.audio.holds_nothing() {
            return;
        }
        let mut keep: HashSet<PathBuf> = HashSet::new();
        // Undo steps share the parts they did not change: look at each once.
        let mut seen: HashSet<*const Part> = HashSet::new();
        let mut add = |project: &Project| {
            for part in project
                .parts
                .iter()
                .chain(std::iter::once(&project.master))
            {
                if !seen.insert(Arc::as_ptr(part)) {
                    continue;
                }
                for clip in &part.clips {
                    if let Some(ClipContent::Audio { file, .. }) = clip.playable() {
                        keep.insert(file.clone());
                    }
                    keep.extend(crate::freeze::block_file(clip));
                }
                keep.extend(crate::freeze::frozen_file(part));
            }
        };
        add(&self.doc.project);
        add(&self.doc.undo.checkpoint);
        add(&self.synced);
        for state in self.doc.undo.history.states() {
            add(&state.snapshot);
        }
        if let Some(shelf) = &self.shelf {
            add(&shelf.project);
            for state in shelf.history.states() {
                add(&state.snapshot);
            }
        }
        keep.extend(self.engine.map.held_files.values().cloned());
        self.audio.retain(&keep);
    }
}
