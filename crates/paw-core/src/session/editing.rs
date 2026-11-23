//! Editing the project: the edit wrapper, flushing to the engine, undo steps.

use super::*;

impl Session {
    /// Change the project ([`Document::edit`](super::Document::edit)). The
    /// engine catches up at the next [`flush`](Self::flush). An edit that
    /// did not fail also forgets which files are there.
    pub fn edit<R>(&mut self, f: impl FnOnce(&mut Project) -> Result<R>) -> Result<R> {
        let result = self.doc.edit(f);
        if result.is_ok() {
            self.files_there.forget();
        }
        result
    }

    /// [`Document::edit_named`](super::Document::edit_named), as
    /// [`edit`](Self::edit) is to [`Document::edit`](super::Document::edit).
    pub fn edit_named<R>(&mut self, f: impl FnOnce(&mut Project) -> Result<R>) -> Result<R> {
        let result = self.doc.edit_named(f);
        if result.is_ok() {
            self.files_there.forget();
        }
        result
    }

    /// Send pending edits to the engine and queue their change events.
    pub fn flush(&mut self) {
        self.engine.handle.collect_garbage();
        self.collect_take();
        if !self.doc.dirty {
            return;
        }
        self.doc.dirty = false;
        // Whatever was added, it has a name before anyone hears it.
        self.doc.project.name_notes(&self.synced);
        let mut ctx = SyncCtx {
            registry: &self.registry,
            sources: &self.sources,
            audio: &mut self.audio,
            live: &mut self.live,
            sample_rate: self.engine.handle.sample_rate as f32,
            warnings: &mut self.doc.warnings,
            offline: false,
            waker: self.engine.handle.waker(),
        };
        let handle = &mut self.engine.handle;
        let mut send = |msg| handle.send(msg);
        let before = self.doc.events.len();
        sync(
            &self.synced,
            &self.doc.project,
            &mut self.engine.map,
            &mut ctx,
            &mut send,
            &mut self.doc.events,
        );
        self.synced = self.doc.project.clone();
        self.remember_for_panic();
        self.note_deferred();
        // Whoever answers edits with edits of their own (in the same undo
        // step) leaves alone a state that was put back: it holds the answer.
        if std::mem::take(&mut self.doc.undo.restoring) {
            for event in &mut self.doc.events[before..] {
                event.restored = true;
            }
        }
    }

    /// Close the current undo step, if anything changed since the last one
    /// ([`Document::checkpoint`](super::Document::checkpoint)).
    pub fn checkpoint(&mut self) {
        // A trial's edits are one step, made when it ends.
        if self.audition.trial.is_some() {
            return;
        }
        if self.doc.checkpoint() {
            self.trim_audio_now_and_then();
        }
    }

    /// Make every clip that refers to a file outside the project the
    /// project's own (`:collect`): the next save writes their files into
    /// its folder. Returns how many.
    pub fn clip_collect(&mut self) -> usize {
        let ids: Vec<Id> = self
            .doc.project
            .all_tracks()
            .flat_map(|t| t.clips.iter().chain(&t.cues))
            .filter(|c| c.source.as_ref().is_some_and(|s| s.is_file()))
            .map(|c| c.id)
            .collect();
        for id in &ids {
            if let Some(clip) = self.doc.project.clip_mut(*id) {
                clip.origin = clip.source.take();
            }
        }
        if !ids.is_empty() {
            self.doc.undo.touched = true;
            self.doc.dirty = true;
        }
        ids.len()
    }

    /// Make every track read from a folder outside the project, and every
    /// chain read from a file outside it, the project's own (`:collect`):
    /// the next save writes them into its folder. Returns how many tracks
    /// and how many chains. Run before `clip_collect`, which then takes
    /// such a track's clips.
    pub fn track_collect(&mut self) -> (usize, usize) {
        let (mut tracks, mut chains) = (0, 0);
        let ids: Vec<Id> = self.doc.project.tracks.iter().map(|t| t.id).collect();
        for id in ids {
            let Some(t) = self.doc.project.track(id) else {
                continue;
            };
            if t.source.is_none() && t.chain_source.is_none() {
                continue;
            }
            let Some(track) = self.doc.project.track_mut(id) else {
                continue;
            };
            if track.source.is_some() {
                track.origin = track.source.take();
                tracks += 1;
            }
            if track.chain_source.is_some() {
                track.chain_origin = track.chain_source.take();
                chains += 1;
            }
        }
        if tracks + chains > 0 {
            self.doc.undo.touched = true;
            self.doc.dirty = true;
        }
        (tracks, chains)
    }

    pub fn undo(&mut self) -> bool {
        self.move_in_history(History::undo).is_some()
    }

    pub fn redo(&mut self) -> bool {
        self.move_in_history(History::redo).is_some()
    }
}
