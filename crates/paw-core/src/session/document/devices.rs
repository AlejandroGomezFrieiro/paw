//! Devices as the model holds them: their place in a chain, their routes
//! and their fields. What loads, asks or calls a plugin is the session's,
//! in `session/devices.rs`.

use std::collections::BTreeMap;

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use paw_engine::MAX_PAIRS;
use serde_json::Value;

use super::Document;
use super::values::{de, de_meta};
use crate::model::{Id, MASTER_ID, Project};

impl Document {
    pub(crate) fn device_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            let (part, index) = p
                .find_device(id)
                .with_context(|| format!("no device {id}"))?;
            let t = p.part_in(part)?;
            t.devices.remove(index);
            t.lanes.retain(|l| l.target.device() != Some(id));
            Ok(())
        })
    }

    /// Move a device to `index` in the chain of `part`.
    pub(crate) fn device_move(&mut self, id: Id, part: Id, index: usize) -> Result<()> {
        self.edit(|p| {
            let (from, at) = p
                .find_device(id)
                .with_context(|| format!("no device {id}"))?;
            if p.part(part).is_none() {
                bail!("no part {part}");
            }
            if let Some(source) = p.device(id).and_then(|d| d.sidechain)
                && from != part
                && (source == part || p.would_cycle(source, part))
            {
                bail!("the device listens to part {source}: on part {part} that would make a loop");
            }
            if let Some(source) = p.device(id).and_then(|d| d.sidechain)
                && from != part
            {
                p.check_route(source, part, crate::model::Route::SideChain)?;
            }
            if from != part {
                for (pair, to) in p.device(id).map(|d| d.outputs.clone()).unwrap_or_default() {
                    check_output(p, part, pair, to)?;
                }
            }
            let source = p.part_in(from)?;
            let device = source.devices.remove(at);
            // In a chain, the device goes where the list puts it: after the
            // top node that holds the device before it (`Chain::fit`).
            if let Some(chain) = &mut source.chain {
                std::sync::Arc::make_mut(chain).root.take(id.into());
            }
            // A device's lanes live on the part it is on, so they go with it.
            let (lanes, keep) = std::mem::take(&mut source.lanes)
                .into_iter()
                .partition(|l| l.target.device() == Some(id) && from != part);
            source.lanes = keep;
            let t = p.part_in(part)?;
            t.devices.insert(index.min(t.devices.len()), device);
            t.lanes.extend::<Vec<_>>(lanes);
            Ok(())
        })
    }

    pub(crate) fn device_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        self.edit(|p| {
            if key == "sidechain" {
                let (part, _) = p
                    .find_device(id)
                    .with_context(|| format!("no device {id}"))?;
                // An empty Lua table arrives as an empty list.
                let source: Option<Id> = match value {
                    Value::Array(a) if a.is_empty() => None,
                    value => de(key, value)?,
                };
                if let Some(source) = source {
                    if p.part(source).is_none() {
                        bail!("no part {source} to take a side-chain from");
                    }
                    if source == MASTER_ID {
                        bail!("the master part feeds nothing, so it cannot be a side-chain");
                    }
                    if source == part {
                        bail!("a device cannot take a side-chain from its own part");
                    }
                    if p.would_cycle(source, part) {
                        bail!(
                            "a side-chain from part {source} to part {part} would make a loop"
                        );
                    }
                    p.check_route(source, part, crate::model::Route::SideChain)?;
                }
                p.device_in(id)?.sidechain = source;
                return Ok(());
            }
            if key == "outputs" {
                let (part, _) = p
                    .find_device(id)
                    .with_context(|| format!("no device {id}"))?;
                let outputs = parse_outputs(value)?;
                for (pair, to) in &outputs {
                    check_output(p, part, *pair, *to)?;
                }
                p.device_in(id)?.outputs = outputs;
                return Ok(());
            }
            let d = p.device_in(id)?;
            match key {
                "sidechain_pre" => d.sidechain_pre = de(key, value)?,
                "bypass" => d.bypass = de(key, value)?,
                "offline" => d.offline = de(key, value)?,
                "meta" => d.meta = de_meta(key, value)?,
                // Base64, as `device_state` gives it; nil for none.
                "state" => {
                    let state: Option<String> = de(key, value)?;
                    if let Some(text) = &state {
                        BASE64
                            .decode(text)
                            .context("a device's state is given in base64")?;
                    }
                    d.state = state;
                }
                _ => bail!("devices have no settable field `{key}`"),
            }
            Ok(())
        })
    }
}

/// A device's routed output pairs from what a script gives: a table of
/// pair number to part (`{ [2] = 5 }`, which may arrive as a list with
/// holes), or nil for none.
fn parse_outputs(value: Value) -> Result<BTreeMap<u32, Id>> {
    let mut out = BTreeMap::new();
    let mut put = |pair: u32, to: &Value| -> Result<()> {
        match to {
            Value::Null => {}
            to => match to.as_u64() {
                Some(to) => {
                    out.insert(pair, to as Id);
                }
                None => bail!("an output pair goes to a part, by its id"),
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
        _ => bail!("a device's outputs are a table of pair number to part"),
    }
    Ok(out)
}

/// Whether a device on `part` may play its pair `pair` into part `to`.
fn check_output(p: &Project, part: Id, pair: u32, to: Id) -> Result<()> {
    if !(2..=MAX_PAIRS as u32).contains(&pair) {
        bail!("output pair {pair} is not one that can be routed: from 2 to {MAX_PAIRS}");
    }
    if part == MASTER_ID {
        bail!("the master feeds nothing, so its devices' outputs cannot be routed");
    }
    if p.part(to).is_none() {
        bail!("no part {to} for output pair {pair}");
    }
    if to == part {
        bail!("output pair {pair} cannot play into the device's own part");
    }
    if to != MASTER_ID && p.would_cycle(part, to) {
        bail!("output pair {pair} into part {to} would make a loop");
    }
    p.check_route(part, to, crate::model::Route::Pair)
}
