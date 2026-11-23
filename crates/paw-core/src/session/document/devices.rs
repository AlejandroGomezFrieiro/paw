//! Devices as the model holds them: their place in a chain, their routes
//! and their fields. What loads, asks or calls a plugin is the session's,
//! in `session/devices.rs`.

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde_json::Value;

use super::Document;
use crate::model::{Id, MASTER_ID};
use crate::session::{de, de_meta, ports};

impl Document {
    pub(crate) fn device_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            let (track, index) = p
                .find_device(id)
                .with_context(|| format!("no device {id}"))?;
            let t = p.track_mut(track).unwrap();
            t.devices.remove(index);
            t.lanes.retain(|l| l.target.device() != Some(id));
            Ok(())
        })
    }

    /// Move a device to `index` in the chain of `track`.
    pub(crate) fn device_move(&mut self, id: Id, track: Id, index: usize) -> Result<()> {
        self.edit(|p| {
            let (from, at) = p
                .find_device(id)
                .with_context(|| format!("no device {id}"))?;
            if p.track(track).is_none() {
                bail!("no track {track}");
            }
            if let Some(source) = p.device(id).and_then(|d| d.sidechain)
                && from != track
                && (source == track || p.would_cycle(source, track))
            {
                bail!("the device listens to track {source}: on track {track} that would make a loop");
            }
            if let Some(source) = p.device(id).and_then(|d| d.sidechain)
                && from != track
            {
                p.check_route(source, track, crate::model::Route::SideChain)?;
            }
            if from != track {
                for (pair, to) in p.device(id).map(|d| d.outputs.clone()).unwrap_or_default() {
                    ports::check_output(p, track, pair, to)?;
                }
            }
            let source = p.track_mut(from).unwrap();
            let device = source.devices.remove(at);
            // In a graph, the device goes where the list puts it: after the
            // top node that holds the device before it (`Graph::fit`).
            if let Some(graph) = &mut source.graph {
                std::sync::Arc::make_mut(graph).root.take(id);
            }
            // A device's lanes live on the track it is on, so they go with it.
            let (lanes, keep) = std::mem::take(&mut source.lanes)
                .into_iter()
                .partition(|l| l.target.device() == Some(id) && from != track);
            source.lanes = keep;
            let t = p.track_mut(track).unwrap();
            t.devices.insert(index.min(t.devices.len()), device);
            t.lanes.extend::<Vec<_>>(lanes);
            Ok(())
        })
    }

    pub(crate) fn device_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        self.edit(|p| {
            if key == "sidechain" {
                let (track, _) = p
                    .find_device(id)
                    .with_context(|| format!("no device {id}"))?;
                // An empty Lua table arrives as an empty list.
                let source: Option<Id> = match value {
                    Value::Array(a) if a.is_empty() => None,
                    value => de(key, value)?,
                };
                if let Some(source) = source {
                    if p.track(source).is_none() {
                        bail!("no track {source} to take a side-chain from");
                    }
                    if source == MASTER_ID {
                        bail!("the master track feeds nothing, so it cannot be a side-chain");
                    }
                    if source == track {
                        bail!("a device cannot take a side-chain from its own track");
                    }
                    if p.would_cycle(source, track) {
                        bail!(
                            "a side-chain from track {source} to track {track} would make a loop"
                        );
                    }
                    p.check_route(source, track, crate::model::Route::SideChain)?;
                }
                p.device_mut(id).unwrap().sidechain = source;
                return Ok(());
            }
            if key == "outputs" {
                let (track, _) = p
                    .find_device(id)
                    .with_context(|| format!("no device {id}"))?;
                let outputs = ports::parse_outputs(value)?;
                for (pair, to) in &outputs {
                    ports::check_output(p, track, *pair, *to)?;
                }
                p.device_mut(id).unwrap().outputs = outputs;
                return Ok(());
            }
            let d = p
                .device_mut(id)
                .with_context(|| format!("no device {id}"))?;
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
