//! Devices as the model holds them: their place in a chain, their routes
//! and their fields. What loads, asks or calls a plugin is the session's,
//! in `session/devices.rs`.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]

use std::collections::BTreeMap;

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use paw_engine::MAX_PAIRS;
use serde::Deserialize;
use serde_json::{Map, Value};

use super::Document;
use super::values::{Given, NoTable, patch};
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
}

patch! {
    /// What `paw.api.device_set` changes in a device: each field as
    /// `device_get` gives it, and what is left out stays.
    #[schemars(rename = "DeviceChanges")]
    pub(crate) struct DevicePatch => DeviceChange, "devices have no settable field" {
        "bypass" bypass: bool => Bypass value,
        #[schemars(extend("x-teal" = "Meta"))]
        "meta" meta: Map<String, Value> => Meta default,
        /// The device is not made: it keeps its state and plays nothing.
        "offline" offline: bool => Offline value,
        /// The part that each further output pair plays into, by the
        /// pair's number from 2; nil or an empty table for none.
        #[schemars(with = "Option<BTreeMap<String, Id>>", extend("x-teal" = "{integer | string: integer}"))]
        "outputs" outputs: PairOutputs => Outputs default,
        /// The part it listens to; nil for none.
        #[schemars(with = "Option<Id>")]
        "sidechain" sidechain: Given<NoTable> => Sidechain clear,
        /// It listens to the side-chain before the fader of its part.
        "sidechain_pre" sidechain_pre: bool => SidechainPre value,
        /// The plugin's state in base64, as `device_state` gives it; nil for
        /// none.
        "state" state: String => State clear,
    }
}

impl Document {
    /// Make the changes of `patch` to device `id`, in the order of their
    /// keys.
    pub(crate) fn device_patch(&mut self, id: Id, patch: DevicePatch) -> Result<()> {
        for change in patch.changes()? {
            self.device_set(id, change)?;
        }
        Ok(())
    }

    /// Make one change of device `id`.
    pub(crate) fn device_set(&mut self, id: Id, change: DeviceChange) -> Result<()> {
        self.edit(|p| {
            let (part, _) = p.find_device(id).with_context(|| format!("no device {id}"))?;
            match change {
                DeviceChange::Sidechain(given) => {
                    let source = Given::id(given, "a side-chain's part")?;
                    if let Some(source) = source {
                        check_sidechain(p, part, source)?;
                    }
                    p.device_in(id)?.sidechain = source;
                }
                DeviceChange::Outputs(PairOutputs(outputs)) => {
                    for (pair, to) in &outputs {
                        check_output(p, part, *pair, *to)?;
                    }
                    p.device_in(id)?.outputs = outputs;
                }
                DeviceChange::SidechainPre(on) => p.device_in(id)?.sidechain_pre = on,
                DeviceChange::Bypass(on) => p.device_in(id)?.bypass = on,
                DeviceChange::Offline(on) => p.device_in(id)?.offline = on,
                DeviceChange::Meta(meta) => p.device_in(id)?.meta = meta,
                DeviceChange::State(state) => {
                    if let Some(text) = &state {
                        BASE64
                            .decode(text)
                            .context("a device's state is given in base64")?;
                    }
                    p.device_in(id)?.state = state;
                }
            }
            Ok(())
        })
    }
}

/// Whether a device on `part` may listen to part `source`.
fn check_sidechain(p: &Project, part: Id, source: Id) -> Result<()> {
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
        bail!("a side-chain from part {source} to part {part} would make a loop");
    }
    p.check_route(source, part, crate::model::Route::SideChain)
}

/// A device's routed output pairs as a script gives them: a table of pair
/// number to part (`{ [2] = 5 }`, which may arrive as a list with holes or
/// with the numbers as text), or nil for none.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct PairOutputs(BTreeMap<u32, Id>);

impl<'de> Deserialize<'de> for PairOutputs {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> std::result::Result<Self, D::Error> {
        deserializer.deserialize_any(PairsVisitor)
    }
}

struct PairsVisitor;

impl<'de> serde::de::Visitor<'de> for PairsVisitor {
    type Value = PairOutputs;

    fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("a table of pair number to part")
    }

    fn visit_seq<A: serde::de::SeqAccess<'de>>(self, mut seq: A) -> std::result::Result<PairOutputs, A::Error> {
        let mut out = BTreeMap::new();
        let mut pair = 0;
        while let Some(to) = seq.next_element::<Option<Id>>()? {
            pair += 1;
            if let Some(to) = to {
                out.insert(pair, to);
            }
        }
        Ok(PairOutputs(out))
    }

    fn visit_map<A: serde::de::MapAccess<'de>>(self, mut map: A) -> std::result::Result<PairOutputs, A::Error> {
        let mut out = BTreeMap::new();
        while let Some(PairNumber(pair)) = map.next_key()? {
            if let Some(to) = map.next_value::<Option<Id>>()? {
                out.insert(pair, to);
            }
        }
        Ok(PairOutputs(out))
    }
}

/// The number of an output pair, as a number or as text.
struct PairNumber(u32);

impl<'de> Deserialize<'de> for PairNumber {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> std::result::Result<Self, D::Error> {
        match Given::<NoTable>::deserialize(deserializer)? {
            #[expect(clippy::cast_sign_loss, reason = "a whole number from 1 up")]
            Given::Number(n) if n >= 1.0 && n.fract() == 0.0 && n <= f64::from(u32::MAX) => Ok(PairNumber(n as u32)),
            Given::Word(word) => word
                .parse()
                .map(PairNumber)
                .map_err(|_| serde::de::Error::custom(format!("output pairs are numbered: `{word}` is not a number"))),
            _ => Err(serde::de::Error::custom("output pairs are numbered from 1")),
        }
    }
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
