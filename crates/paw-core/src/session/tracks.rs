//! Tracks: what a change of a track does beyond the model. The model's
//! part is in `session/document/tracks.rs`.

use super::*;

impl Session {
    /// Set `key` of track `id` ([`Document::track_set`]). A fader or pan
    /// knob moved while the song plays writes automation
    /// (`session/write.rs`).
    pub(crate) fn track_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        if let Some(moved) = self.doc.track_set(id, key, value)? {
            self.touch(id, moved.target, moved.before, moved.to);
        }
        Ok(())
    }
}
