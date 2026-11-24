//! Editing the project: flushing to the engine, undo steps. The edits
//! themselves are [`Document::edit`](super::Document::edit)'s.

use super::*;

impl Session {
    /// Send pending edits to the engine and queue their change events.
    /// Step 4a of a turn, also `paw.api.flush`: write the automation being
    /// held, push the edits to the engine, read files ahead of the
    /// playhead, and take what the hashing of the media learned.
    pub(crate) fn push_edits(&mut self) {
        self.write_automation();
        self.flush();
        self.read_ahead();
        self.poll_media();
    }

    pub(crate) fn flush(&mut self) {
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
            bell: self.bell.bell(crate::doorbell::Woken::PLUGINS),
            now: self.now,
            kinds: &self.doc.split_kinds,
            modifiers: &self.doc.modifier_kinds,
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
    pub(crate) fn checkpoint(&mut self) {
        // A trial's edits are one step, made when it ends.
        if self.audition.trial.is_some() {
            return;
        }
        if self.doc.checkpoint(self.now, history::now()) {
            self.trim_audio_now_and_then();
        }
    }

    /// Make every clip that refers to a file outside the project the
    /// project's own ([`Document::clip_collect`]), each whose file is there.
    pub(crate) fn clip_collect(&mut self) -> usize {
        self.doc.clip_collect(Path::is_file)
    }

    pub(crate) fn undo(&mut self) -> bool {
        self.move_in_history(History::undo).is_some()
    }

    pub(crate) fn redo(&mut self) -> bool {
        self.move_in_history(History::redo).is_some()
    }
}
