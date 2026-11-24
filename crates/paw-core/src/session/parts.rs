//! Parts: what a change of a part does beyond the model. The model's
//! part is in `session/document/parts.rs`.

use super::*;

impl Session {
    /// Set `key` of part `id` ([`Document::part_set`]). A fader or pan
    /// knob moved while the song plays writes automation
    /// (`session/write.rs`).
    pub(crate) fn part_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        if let Some(moved) = self.doc.part_set(id, key, value)? {
            self.touch(id, moved.target, moved.before, moved.to);
        }
        Ok(())
    }
}
