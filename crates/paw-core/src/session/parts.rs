//! Parts: what a change of a part does beyond the model. The model's
//! part is in `session/document/parts.rs`.

use super::*;

impl Session {
    /// Make the changes of `patch` to part `id`, in the order of their keys
    /// ([`Document::part_set`]). A fader or pan knob moved while the song
    /// plays writes automation (`session/write.rs`).
    pub(crate) fn part_patch(&mut self, id: Id, patch: PartPatch) -> Result<()> {
        for change in patch.changes()? {
            if let Some(moved) = self.doc.part_set(id, change)? {
                self.touch(id, moved.target, moved.before, moved.to);
            }
        }
        Ok(())
    }
}
