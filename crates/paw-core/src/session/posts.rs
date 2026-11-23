//! Data for every device of a kind: what an extension keeps its devices fed
//! with, whichever of them exist now and whichever are made later, a
//! render's private ones included.

use std::sync::Arc;

use super::Session;

impl Session {
    /// Post `data` under `topic` to every device of `kind`: each one there is
    /// now gets it through its `call` at once, and the kind keeps it as the
    /// latest of that topic for every one made later, before its first
    /// block. `None` forgets the topic. Returns, for devices that refused
    /// it, their ids and why.
    pub(crate) fn device_post(
        &mut self,
        kind: &str,
        topic: &str,
        data: Option<&[u8]>,
    ) -> Vec<(u64, String)> {
        self.flush();
        let data: Option<Arc<[u8]>> = data.map(Arc::from);
        let kind = self.registry.resolve(kind).to_string();
        let kind = kind.as_str();
        self.registry.post(kind, topic, data.clone());
        let Some(data) = data else {
            return Vec::new();
        };
        let mut refused = Vec::new();
        for (id, live) in self.live.iter_mut() {
            let Some(controller) = live.controller.as_mut() else {
                continue;
            };
            if self
                .doc.project
                .device(*id)
                .is_some_and(|d| self.registry.resolve(&d.kind) == kind)
                && let Err(err) = controller.call(topic, &data)
            {
                refused.push((*id, format!("{err:#}")));
            }
        }
        refused
    }
}
