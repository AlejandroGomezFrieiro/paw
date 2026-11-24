//! What a device takes and gives besides its main stereo pair: whether it
//! listens to a side-chain and the names of its output pairs, as the
//! running instance says. Where its further pairs are routed is the
//! document's (`document/devices.rs`).

use paw_engine::Ports;

use super::Session;
use crate::model::Id;

impl Session {
    /// The ports of a device as it runs; none known for one that is not
    /// running (not made yet, offline, or missing).
    pub(crate) fn device_ports(&self, id: Id) -> Ports {
        let Some(live) = self.live.get(&id) else {
            return Ports::default();
        };
        match &live.controller {
            Some(controller) => controller.ports(),
            None => self
                .doc.project
                .device(id)
                .and_then(|d| self.registry.get(&d.kind))
                .map(|factory| factory.ports())
                .unwrap_or_default(),
        }
    }
}
