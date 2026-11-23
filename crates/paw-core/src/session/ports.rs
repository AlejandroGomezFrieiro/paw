//! What a device takes and gives besides its main stereo pair: whether it
//! listens to a side-chain and the names of its output pairs, as the
//! running instance says, and where its further pairs are routed.

use std::collections::BTreeMap;

use anyhow::{Result, bail};
use paw_engine::{MAX_PAIRS, Ports};
use serde_json::{Value, json};

use super::Session;
use crate::model::{Id, MASTER_ID, Project};

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

pub(super) fn ports_json(ports: &Ports) -> Value {
    json!({ "sidechain": ports.sidechain, "outputs": ports.outputs })
}

/// A device's routed output pairs from what a script gives: a table of
/// pair number to track (`{ [2] = 5 }`, which may arrive as a list with
/// holes), or nil for none.
pub(super) fn parse_outputs(value: Value) -> Result<BTreeMap<u32, Id>> {
    let mut out = BTreeMap::new();
    let mut put = |pair: u32, to: &Value| -> Result<()> {
        match to {
            Value::Null => {}
            to => match to.as_u64() {
                Some(to) => {
                    out.insert(pair, to as Id);
                }
                None => bail!("an output pair goes to a track, by its id"),
            },
        }
        Ok(())
    };
    match value {
        Value::Null => {}
        Value::Array(list) => {
            for (i, to) in list.iter().enumerate() {
                put(i as u32 + 1, to)?;
            }
        }
        Value::Object(map) => {
            for (pair, to) in &map {
                let Ok(pair) = pair.parse::<u32>() else {
                    bail!("output pairs are numbered: `{pair}` is not a number");
                };
                put(pair, to)?;
            }
        }
        _ => bail!("a device's outputs are a table of pair number to track"),
    }
    Ok(out)
}

/// Whether a device on `track` may play its pair `pair` into track `to`.
pub(super) fn check_output(p: &Project, track: Id, pair: u32, to: Id) -> Result<()> {
    if !(2..=MAX_PAIRS as u32).contains(&pair) {
        bail!("output pair {pair} is not one that can be routed: from 2 to {MAX_PAIRS}");
    }
    if track == MASTER_ID {
        bail!("the master feeds nothing, so its devices' outputs cannot be routed");
    }
    if p.track(to).is_none() {
        bail!("no track {to} for output pair {pair}");
    }
    if to == track {
        bail!("output pair {pair} cannot play into the device's own track");
    }
    if to != MASTER_ID && p.would_cycle(track, to) {
        bail!("output pair {pair} into track {to} would make a loop");
    }
    p.check_route(track, to, crate::model::Route::Pair)
}
