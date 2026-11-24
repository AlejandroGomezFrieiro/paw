//! The lookup of a lane for an edit, beside `Project::part_in`,
//! `clip_in` and `device_in` in model.rs.

use crate::model::{Id, Lane, Project};

impl Project {
    /// Lane `id`, to change, or the error "no lane `id`".
    pub(crate) fn lane_in(&mut self, id: Id) -> anyhow::Result<&mut Lane> {
        self.lane_mut(id).ok_or_else(|| anyhow::anyhow!("no lane {id}"))
    }
}
