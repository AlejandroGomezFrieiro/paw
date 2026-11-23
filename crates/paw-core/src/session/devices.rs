//! Devices on tracks: adding, removing, parameters, states, presets and calls.

use crate::events::{DeviceTrouble, Item, KernelEvent as E, ParamTouched, StateApplied};
use paw_engine::DeviceFormat;
use super::*;

/// What `paw.api.device_find` looks for; each part is optional.
#[derive(Default, serde::Deserialize)]
#[serde(default)]
pub(crate) struct DeviceQuery {
    pub kind: Option<String>,
    pub format: Option<String>,
    pub id: Option<String>,
    pub name: Option<String>,
    pub vendor: Option<String>,
    pub all: bool,
}

fn type_json(info: &paw_engine::DeviceInfo) -> Value {
    let params: Vec<Value> = info.params.iter().map(param_json).collect();
    json!({
        "kind": info.kind, "name": info.name, "category": info.category,
        "format": info.format, "vendor": info.vendor, "params": params,
        "id": info.id, "version": info.version, "features": info.features,
    })
}

impl Session {
    pub(crate) fn device_types(&self) -> Value {
        Value::Array(self.registry.iter().map(|f| type_json(f.info())).collect())
    }

    /// The kinds of device that answer a query, best first: by kind (an
    /// old name of a kind too), else by the plugin's own id, else by name
    /// and vendor, else by name in any case. Each test looks only at the
    /// kinds of `format` when it is given. The list of all kinds is not
    /// made, so this is quick with many plugins.
    pub(crate) fn device_find(&self, q: &DeviceQuery) -> Vec<Value> {
        // A word that names no format (`vst`) finds nothing.
        let format = q.format.as_deref().map(|f| match f.to_ascii_lowercase().as_str() {
            "built in" | "built-in" => Some(DeviceFormat::Builtin),
            other => other.parse::<DeviceFormat>().ok(),
        });
        let in_format =
            |info: &paw_engine::DeviceInfo| format.is_none_or(|f| f == Some(info.format));
        if let Some(kind) = &q.kind {
            return self
                .registry
                .get(kind)
                .map(|f| f.info())
                .filter(|i| in_format(i))
                .map(|i| vec![type_json(i)])
                .unwrap_or_default();
        }
        let infos = || self.registry.iter().map(|f| f.info()).filter(|i| in_format(i));
        let mut out: Vec<Value> = Vec::new();
        if let Some(id) = q.id.as_deref().filter(|id| !id.is_empty()) {
            // A VST3 class id is written in either case.
            out.extend(infos().filter(|i| !i.id.is_empty() && i.id.eq_ignore_ascii_case(id)).map(type_json));
        }
        if out.is_empty()
            && let Some(name) = q.name.as_deref()
        {
            let vendor = q.vendor.as_deref().filter(|v| !v.is_empty());
            out.extend(
                infos()
                    .filter(|i| {
                        i.name == name && (vendor.is_none() || i.vendor.is_empty() || Some(i.vendor.as_str()) == vendor)
                    })
                    .map(type_json),
            );
            if out.is_empty() {
                out.extend(infos().filter(|i| i.name.eq_ignore_ascii_case(name)).map(type_json));
            }
        }
        if q.id.is_none() && q.name.is_none() {
            out.extend(infos().map(type_json));
        }
        out
    }

    /// Every parameter of a device with its current value, and its
    /// description.
    fn device_params(
        &self,
        id: Id,
        track: Id,
        d: &crate::model::DeviceInst,
        live: Option<&crate::sync::LiveDevice>,
    ) -> (serde_json::Map<String, Value>, Vec<Value>) {
        // Every parameter with its current value: what the project sets,
        // else what the plugin reports (from its own state), else the default.
        let mut params = serde_json::Map::new();
        let mut infos = Vec::new();
        // The parameters a lane of the track moves.
        let automated: Vec<&str> = self
            .doc.project
            .track(track)
            .unwrap()
            .lanes
            .iter()
            .filter_map(|l| match &l.target {
                Target::Param { device, param } if *device == id && l.enabled => {
                    Some(param.as_str())
                }
                _ => None,
            })
            .collect();
        for (i, p) in live
            .map(|l| l.params.as_slice())
            .unwrap_or(&[])
            .iter()
            .enumerate()
        {
            let reported = || {
                live.and_then(|l| l.controller.as_ref())
                    .and_then(|c| c.value(i))
            };
            let value = d
                .params
                .get(&p.key)
                .copied()
                .or_else(reported)
                .unwrap_or(p.default as f64);
            params.insert(p.key.clone(), json!(value));
            let mut info = param_json(p);
            info["index"] = json!(i + 1);
            info["automated"] = json!(automated.contains(&p.key.as_str()));
            infos.push(info);
        }
        (params, infos)
    }

    pub(crate) fn device_view(&self, id: Id) -> Result<Value> {
        let (track, index) = self
            .doc.project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        let d = &self.doc.project.track(track).unwrap().devices[index];
        let info = self.registry.get(&d.kind).map(|f| f.info());
        let live = self.live.get(&id);
        let (mut params, infos) = self.device_params(id, track, d, live);
        // `running`, `loading` (being made apart: see session/loading.rs),
        // `stopped`, `offline` (set so: not made at all) or `missing` (not
        // installed).
        let loading = self.loads.loading(id);
        let stopped = live
            .and_then(|l| l.stopped.clone())
            .or_else(|| self.loads.failed(id).map(str::to_string));
        let status = if d.offline {
            "offline"
        } else if info.is_none() {
            "missing"
        } else if loading {
            "loading"
        } else if stopped.is_some() || live.is_none() {
            "stopped"
        } else {
            "running"
        };
        // Whether the device has a window of its own, and whether it is showing.
        let editor = live
            .and_then(|l| l.controller.as_ref())
            .filter(|c| c.has_editor())
            .map(|c| if c.editor_open() { "open" } else { "closed" });
        // A device that is not running still has the values the project
        // keeps for it.
        if live.is_none() {
            for (key, value) in &d.params {
                params.insert(key.clone(), json!(value));
            }
        }
        let name = info.map(|i| &i.name).or(d.name.as_ref()).unwrap_or(&d.kind);
        // Who made it and which it is, as its format names it.
        let plugin = info.filter(|i| !i.id.is_empty()).map(|i| {
            json!({
                "format": i.format, "id": i.id, "name": i.name, "vendor": i.vendor,
                "version": i.version,
            })
        });
        Ok(json!({
            "plugin": plugin,
            "id": d.id, "kind": d.kind, "name": name, "offline": d.offline,
            "format": info.map_or("", |i| i.format.as_str()),
            "track": track, "index": index + 1, "bypass": d.bypass, "params": params,
            // The parameters the project sets, over what the plugin's state says.
            "overrides": d.params,
            "param_info": infos, "meta": d.meta, "editor": editor,
            // Not running: not installed, not made yet, or made and gone.
            "missing": live.is_none() && !loading && !d.offline,
            // Why the device has stopped working, for a plugin that crashed,
            // hung, or could not be made.
            "stopped": stopped,
            "status": status,
            // The track it listens to, and whether it can listen at all.
            "sidechain": d.sidechain, "sidechain_pre": d.sidechain_pre,
            // Where its further output pairs play, by pair number.
            "outputs": d.outputs,
            "ports": ports::ports_json(&self.device_ports(id)),
        }))
    }

    pub(crate) fn device_add(&mut self, track: Id, kind: &str, opts: DeviceOpts) -> Result<Id> {
        if self.registry.get(kind).is_none() {
            bail!("no device kind `{kind}`");
        }
        let id = self.doc.new_id();
        // A plugin's name, for when it is not installed.
        let name = self
            .registry
            .get(kind)
            .map(|f| f.info())
            .filter(|info| info.format != DeviceFormat::Builtin)
            .map(|info| info.name.clone());
        self.doc.edit(|p| {
            let t = p
                .track_mut(track)
                .with_context(|| format!("no track {track}"))?;
            let device = DeviceInst {
                id,
                kind: kind.into(),
                bypass: false,
                params: BTreeMap::new(),
                state: opts.state.clone(),
                meta: Default::default(),
                loaded: 0,
                name: name.clone(),
                offline: false,
                sidechain: None,
                sidechain_pre: false,
                outputs: BTreeMap::new(),
                param_ids: BTreeMap::new(),
                files: BTreeMap::new(),
            };
            let index = opts
                .index
                .map_or(usize::MAX, |i| i.saturating_sub(1))
                .min(t.devices.len());
            t.devices.insert(index, Arc::new(device));
            Ok(())
        })?;
        // Create it now: a plugin's parameters are only known once it exists,
        // and a plugin that fails to load should fail here, not later.
        let before = self.doc.warnings.len();
        self.flush();
        let outcome = if self.live.contains_key(&id) || self.loads.loading(id) {
            opts.params
                .iter()
                .try_for_each(|(name, value)| self.device_set_param(id, name, *value))
        } else {
            Err(anyhow!(
                self.doc.warnings
                    .drain(before..)
                    .next_back()
                    .unwrap_or_else(|| format!("could not load `{kind}`"))
            ))
        };
        if let Err(err) = outcome {
            self.doc.device_remove(id)?;
            return Err(err);
        }
        Ok(id)
    }



    /// A parameter of a loaded device, by key or by its display name.
    pub(super) fn param_info(&mut self, id: Id, name: &str) -> Result<ParamInfo> {
        let kind = self
            .doc.project
            .device(id)
            .with_context(|| format!("no device {id}"))?
            .kind
            .clone();
        self.flush();
        self.await_device(id);
        let Some(live) = self.live.get(&id) else {
            bail!("device `{kind}` is not loaded");
        };
        find_param(&live.params, name)
            .map(|at| live.params[at].clone())
            .with_context(|| format!("device `{kind}` has no parameter `{name}`"))
    }

    /// A parameter of a loaded device as [`param_json`] describes it, with
    /// its value now and that value as the device writes it.
    pub(crate) fn device_param(&mut self, id: Id, name: &str) -> Result<Value> {
        let param = self.param_info(id, name)?;
        let view = self.device_view(id)?;
        let at = view["param_info"]
            .as_array()
            .and_then(|list| list.iter().position(|p| p["key"] == json!(param.key)))
            .context("the parameter is gone")?;
        let mut out = view["param_info"][at].clone();
        let value = view["params"][&param.key].as_f64().unwrap_or(param.default as f64);
        out["value"] = json!(value);
        out["text"] = json!(self.param_text(id, &param.key, value)?);
        Ok(out)
    }

    /// A value of a parameter as text: as the device writes it (a plugin's
    /// own "440 Hz"), else as [`ParamInfo::format`] does.
    pub(crate) fn param_text(&mut self, id: Id, name: &str, value: f64) -> Result<String> {
        let value = finite("a parameter value", value)?;
        let param = self.param_info(id, name)?;
        let live = self.live.get_mut(&id).context("the device is not loaded")?;
        let at = find_param(&live.params, &param.key).unwrap();
        let own = !crate::sync::is_host(&live.params, at);
        let text = live
            .controller
            .as_mut()
            .filter(|_| own)
            .and_then(|c| c.value_text(at, value));
        Ok(text.unwrap_or_else(|| param.format(value)))
    }

    /// The value a text stands for, for a parameter: as the device reads
    /// it, else as [`ParamInfo::parse`] does.
    pub(crate) fn param_parse(&mut self, id: Id, name: &str, text: &str) -> Result<f64> {
        let param = self.param_info(id, name)?;
        let live = self.live.get_mut(&id).context("the device is not loaded")?;
        let at = find_param(&live.params, &param.key).unwrap();
        let own = !crate::sync::is_host(&live.params, at);
        let value = live
            .controller
            .as_mut()
            .filter(|_| own)
            .and_then(|c| c.text_value(at, text))
            .or_else(|| param.parse(text));
        value.with_context(|| format!("`{text}` is not a value of `{}`", param.name))
    }

    /// Set a parameter by key, or by its display name.
    pub(crate) fn device_set_param(&mut self, id: Id, name: &str, value: f64) -> Result<()> {
        let value = finite("a parameter value", value)?;
        let param = self.param_info(id, name)?;
        let key = param.key.clone();
        let value = (value as f32).clamp(param.min, param.max) as f64;
        let touched = ParamTouched { device: id, param: key.clone(), id: param.stable_id().to_string(), from: "host".into(), value: None };
        self.doc.emit(E::ParamTouched(touched));
        if self.play.playing
            && let Some((track, _)) = self.doc.project.find_device(id)
            && self.auto_mode(track).writes()
        {
            let before = self.device_view(id)?["params"][&key].as_f64();
            let target = Target::Param {
                device: id,
                param: key.clone(),
            };
            self.touch(track, target, before.unwrap_or(value), value);
        }
        let name = format!("param {id} {key}");
        self.doc.edit(|p| {
            p.device_mut(id).unwrap().params.insert(key, value);
            Ok(())
        })?;
        self.doc.swept(name);
        Ok(())
    }

    /// Ask every plugin for its state and store it in the project, so that
    /// saving, rendering and restarting the engine reproduce what is sounding.
    ///
    /// Parameters set through the project are not read back from the plugin:
    /// the project is the authority for those, and they are applied again on
    /// top of the state whenever the plugin is recreated.
    pub(crate) fn capture_states(&mut self) {
        self.flush();
        let mut captured = Vec::new();
        let mut kept = Vec::new();
        let driven = statelanes::driven(&self.doc.project);
        for (id, live) in &mut self.live {
            // A device that stopped working has no state to give: the
            // project keeps the one it had, and its stop was told already.
            // One a state lane drives holds the lane's state, not its own.
            if live.stopped.is_some() || driven.contains(id) {
                continue;
            }
            let Some(controller) = live.controller.as_mut() else {
                continue;
            };
            match controller.save_state() {
                Ok(Some(bytes)) => captured.push((*id, BASE64.encode(bytes))),
                Ok(None) => {}
                Err(err) => self
                    .doc.warnings
                    .push(format!("could not save plugin state: {err:#}")),
            }
            // The files it keeps beside its state (an ARA archive).
            if live.attached {
                match controller
                    .call(paw_engine::device::FILE_SAVE, &[])
                    .and_then(|packed| paw_engine::device::unpack_files(&packed))
                {
                    Ok(files) => kept.push((
                        *id,
                        files
                            .into_iter()
                            .map(|(name, bytes)| (name, BASE64.encode(bytes)))
                            .collect::<BTreeMap<_, _>>(),
                    )),
                    Err(err) => self
                        .doc.warnings
                        .push(format!("could not save the files of a plugin: {err:#}")),
                }
            }
        }
        for (id, state) in captured {
            if let Some(device) = self.doc.project.device_mut(id) {
                device.state = Some(state);
            }
        }
        for (id, files) in kept {
            if let Some(device) = self.doc.project.device_mut(id) {
                device.files = files;
            }
        }
        // This is bookkeeping, not an edit: nothing for the engine to do.
        self.synced = self.doc.project.clone();
    }

    /// A plugin's state as it is now, base64 encoded, for making a copy of
    /// the device with [`DeviceOpts::state`]. None for devices that keep no
    /// state beyond their parameters.
    pub(crate) fn device_state(&mut self, id: Id) -> Result<Option<String>> {
        self.doc.project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        self.flush();
        self.await_device(id);
        let Some(controller) = self.live.get_mut(&id).and_then(|l| l.controller.as_mut()) else {
            return Ok(None);
        };
        Ok(controller.save_state()?.map(|bytes| BASE64.encode(bytes)))
    }

    /// Load a preset into a device as one edit, which undo takes back: the
    /// plugin's state (base64, none for a device that keeps none), the
    /// parameters the preset sets, and its name, kept as `meta.preset`.
    /// With `factory`, the plugin first loads one of its own presets by that
    /// id, and the state it has then is what is kept.
    pub(crate) fn device_load(&mut self, id: Id, load: PresetLoad) -> Result<()> {
        self.doc.project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        self.flush();
        let first = self.trial_loads(id);
        let controller = self.live.get_mut(&id).and_then(|l| l.controller.as_mut());
        // What the plugin holds now goes into the step before this one, so
        // that undo comes back to it and not to an older state (in a trial,
        // what it held before the trial's first preset).
        let mut state = load.state;
        if let Some(controller) = controller {
            if let Some(bytes) = first.then(|| controller.save_state()).and_then(|s| s.ok().flatten()) {
                let now = BASE64.encode(bytes);
                for snapshot in [&mut self.doc.project, &mut self.doc.undo.checkpoint, &mut self.synced] {
                    if let Some(device) = snapshot.device_mut(id) {
                        device.state = Some(now.clone());
                    }
                }
            }
            let request = match (&load.factory, &load.call) {
                (Some(_), Some(_)) => bail!("give a preset load `factory` or `call`, not both"),
                (Some(preset), None) => Some((paw_engine::device::method::PRESET_LOAD, preset.as_bytes(), 10, 30)),
                // A file the plugin loads in the background (a model) can
                // take longer than one of its own presets, or much less:
                // look more often, for up to a second.
                (None, Some(call)) => Some((call.method.as_str(), call.data.as_bytes(), 200, 5)),
                (None, None) => None,
            };
            if let Some((method, data, tries, wait)) = request {
                let before = controller.save_state().ok().flatten();
                controller.call(method, data)?;
                // Some plugins finish loading on their audio thread: give
                // them a moment before reading back what they hold.
                let mut after = controller.save_state()?;
                for _ in 0..tries {
                    if after != before {
                        break;
                    }
                    std::thread::sleep(std::time::Duration::from_millis(wait));
                    controller.idle();
                    after = controller.save_state()?;
                }
                state = after.map(|bytes| BASE64.encode(bytes));
            }
        } else if load.factory.is_some() {
            bail!("this device has no presets of its own");
        } else if load.call.is_some() {
            bail!("this device takes no calls");
        }
        if let Some(text) = &state {
            BASE64
                .decode(text)
                .context("a preset's state is given in base64")?;
        }
        // The plugin already holds the new state when it loaded one of its
        // own presets or answered a call.
        let already = load.factory.is_some() || load.call.is_some();
        self.doc.edit(|p| {
            let d = p.device_mut(id).unwrap();
            d.state = state;
            d.params = load.params;
            d.loaded = d.loaded.wrapping_add(1);
            match load.name {
                Some(name) => d.meta.insert("preset".into(), Value::String(name)),
                None => d.meta.remove("preset"),
            };
            Ok(())
        })?;
        // Loading the state it gave back into it again would only cost time.
        if already && let Some(device) = self.doc.project.device(id).cloned() {
            let synced_device = self.synced.device_mut(id);
            if let Some(synced_device) = synced_device {
                *synced_device = (*device).clone();
            }
            self.doc.emit(E::DeviceChanged(Item::on(id, None)));
            self.doc.emit(E::changed());
        }
        Ok(())
    }

    /// Start a device again that has stopped working, or that never loaded:
    /// a new instance, with the state the project last had of it and the
    /// parameters set in the project. The project itself does not change.
    pub(crate) fn device_restart(&mut self, id: Id) -> Result<()> {
        let (track, _) = self
            .doc.project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        if self.doc.project.device(id).is_some_and(|d| d.offline) {
            bail!("the device is offline: set it online to start it");
        }
        self.flush();
        // Take it out of the engine and put it back, behind the project's back.
        let mut without = self.doc.project.clone();
        if let Some(track) = without.track_mut(track) {
            track.devices.retain(|d| d.id != id);
        }
        let mut quiet = Vec::new();
        {
            let mut ctx = SyncCtx {
                registry: &self.registry,
                sources: &self.sources,
                audio: &mut self.audio,
                live: &mut self.live,
                sample_rate: self.engine.handle.sample_rate as f32,
                warnings: &mut self.doc.warnings,
                offline: false,
                waker: self.engine.handle.waker(),
            };
            let handle = &mut self.engine.handle;
            let mut send = |msg| handle.send(msg);
            sync(
                &self.synced,
                &without,
                &mut self.engine.map,
                &mut ctx,
                &mut send,
                &mut quiet,
            );
        }
        self.synced = without;
        self.doc.dirty = true;
        let before = self.doc.events.len();
        self.flush();
        // Nothing was added to the project: say only that the device changed.
        self.doc.events.truncate(before);
        self.doc.emit(E::DeviceChanged(Item::on(id, Some(track))));
        if !self.live.contains_key(&id) && !self.loads.loading(id) {
            let why = self
                .doc.warnings
                .pop()
                .unwrap_or_else(|| "it could not be started".into());
            bail!("{why}");
        }
        Ok(())
    }

    /// Housekeeping for plugins: runs their editors and picks up what they
    /// changed by themselves. Call regularly from the main thread.
    pub(crate) fn idle(&mut self) {
        // The stepped engine plays up to the clock first: what it played is
        // then heard of below.
        self.run_stepped_audio();
        // A take whose file could not be written stops; what it has is kept.
        if self.rec.take.as_ref().is_some_and(|t| t.shared.failed()) {
            self.stop();
        }
        self.poll_takes();
        self.render_poll();
        self.play_states();
        self.poll_preview();
        self.poll_loads();
        self.poll_bakes();
        self.watch_devices();
        self.poll_file_changes();
        let mut scan = self.scan_devices();
        self.emit_device_scan(&mut scan);
        self.apply_device_scan(scan);
    }

    /// Look at each live device once: engine faults, health, latency and what
    /// its own window changed.
    fn scan_devices(&mut self) -> DeviceScan {
        let mut scan = DeviceScan::default();
        for (id, live) in &mut self.live {
            // Any device, built in or not, that panicked or put out NaN or
            // infinity: the engine has bypassed or silenced it.
            if let Some(&slot) = self.engine.map.devices.get(id) {
                let fault = self
                    .engine.handle
                    .shared
                    .fault(slot, paw_engine::guard::Fault::NOT_FINITE);
                if fault.contains(paw_engine::guard::Fault::PANICKED) && live.stopped.is_none() {
                    let why =
                        "it crashed while processing; it is bypassed until restarted".to_string();
                    live.stopped = Some(why.clone());
                    scan.stopped.push((*id, why));
                }
                if fault.contains(paw_engine::guard::Fault::NOT_FINITE) {
                    scan.invalid.push(*id);
                }
            }
            let Some(controller) = live.controller.as_mut() else {
                continue;
            };
            let was_open = controller.editor_open();
            controller.idle();
            // A state given before is taken on once its controller no
            // longer waits for it (see `Controller::state_pending`).
            if let Some(seq) = live.take_state_applied() {
                scan.applied.push((*id, seq));
            }
            let Some(controller) = live.controller.as_mut() else {
                continue;
            };
            if live.stopped.is_none()
                && let Some(why) = controller.health()
            {
                live.stopped = Some(why.clone());
                scan.stopped.push((*id, why));
            }
            let latency = controller.latency();
            if latency != live.latency {
                live.latency = latency;
                scan.latency_changed = true;
            }
            let changes = controller.take_changes();
            // The echo of a state it was given only mirrors the state, which
            // the project already holds: nothing was edited.
            let mut keys: Vec<String> = Vec::new();
            for change in changes.iter().filter(|c| c.edit) {
                if let Some(param) = live.params.get(change.index) {
                    keys.push(param.key.clone());
                    scan.moved.push((*id, param.key.clone(), param.stable_id().to_string(), change.value));
                }
            }
            if !changes.is_empty() || was_open != controller.editor_open() {
                scan.changed.push((*id, keys));
            }
        }
        scan
    }

    /// Tell the frontends about the parameters moved in a plugin's window and
    /// the devices that stopped or put out NaN or infinity.
    fn emit_device_scan(&mut self, scan: &mut DeviceScan) {
        let moved = std::mem::take(&mut scan.moved);
        let stopped = std::mem::take(&mut scan.stopped);
        let invalid = std::mem::take(&mut scan.invalid);
        let applied = std::mem::take(&mut scan.applied);
        for (device, param, stable, value) in moved {
            // The parameter last moved in a plugin's own window, for
            // `:param.last` and for the frontends to show.
            let touched = ParamTouched { device, param: param.clone(), id: stable, from: "editor".into(), value: Some(value) };
            self.doc.emit(E::ParamTouched(touched));
            if let Some((track, _)) = self.doc.project.find_device(device) {
                self.touch(track, Target::Param { device, param }, value, value);
            }
        }
        for (device, why) in stopped {
            let Some((track, _)) = self.doc.project.find_device(device) else {
                continue;
            };
            let kind = self.doc.project.device(device).map_or("", |d| d.kind.as_str());
            let name = self
                .registry
                .get(kind)
                .map_or(kind.to_string(), |f| f.info().name.clone());
            self.doc.emit(E::DeviceStopped(DeviceTrouble { device, track, name, reason: Some(why), loading: false }));
        }
        for device in invalid {
            let Some((track, _)) = self.doc.project.find_device(device) else {
                continue;
            };
            let kind = self.doc.project.device(device).map_or("", |d| d.kind.as_str());
            let name = self
                .registry
                .get(kind)
                .map_or(kind.to_string(), |f| f.info().name.clone());
            self.doc.emit(E::DeviceInvalid(DeviceTrouble { device, track, name, reason: None, loading: false }));
        }
        for (device, seq) in applied {
            let Some((track, _)) = self.doc.project.find_device(device) else {
                continue;
            };
            let kind = self.doc.project.device(device).map_or("", |d| d.kind.as_str());
            let name = self.device_name(kind);
            self.doc.emit(E::DeviceStateApplied(StateApplied { device, track, name, seq }));
        }
    }

    /// The plugin's own changes: lining up the tracks again for a new latency,
    /// and dropping the project's overrides of values the plugin now holds.
    fn apply_device_scan(&mut self, scan: DeviceScan) {
        if scan.latency_changed {
            // The tracks have to be lined up again.
            self.doc.dirty = true;
            self.flush();
        }
        if scan.changed.is_empty() {
            return;
        }
        self.flush();
        for (id, keys) in scan.changed {
            // The plugin now holds a value the project did not set. Stop
            // overriding it: the plugin's own state is what carries it from here.
            for snapshot in [&mut self.doc.project, &mut self.doc.undo.checkpoint] {
                let overridden = snapshot
                    .device(id)
                    .is_some_and(|d| keys.iter().any(|key| d.params.contains_key(key)));
                if overridden && let Some(device) = snapshot.device_mut(id) {
                    device.params.retain(|key, _| !keys.contains(key));
                }
            }
            let track = self.doc.project.find_device(id).map(|(track, _)| track);
            self.doc.emit(E::DeviceChanged(Item::on(id, track)));
        }
        // Nothing here needs sending to the engine: the plugin already has it.
        self.synced = self.doc.project.clone();
        self.doc.emit(E::changed());
    }

    /// Show or hide a plugin's own window. Returns whether it is open afterwards.
    pub(crate) fn device_editor(&mut self, id: Id, open: Option<bool>) -> Result<bool> {
        self.flush();
        self.await_device(id);
        let (track, _) = self
            .doc.project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        let track = self
            .doc.project
            .track(track)
            .map(|t| t.name.clone())
            .unwrap_or_default();
        let name = self
            .doc.project
            .device(id)
            .and_then(|d| self.registry.get(&d.kind))
            .map(|f| f.info().name.clone());
        let controller = self
            .live
            .get_mut(&id)
            .and_then(|live| live.controller.as_mut())
            .filter(|controller| controller.has_editor())
            .context("this device has no editor window")?;
        if open.unwrap_or(!controller.editor_open()) {
            controller.open_editor(&format!("{} · {track}", name.unwrap_or_default()))?;
        } else {
            controller.close_editor();
        }
        let open = controller.editor_open();
        self.doc.emit(E::DeviceChanged(Item::on(id, None)));
        self.doc.emit(E::changed());
        Ok(open)
    }

    /// Pass a script's request to the main-thread side of a device.
    /// What a plugin calls its keys (CLAP's `note-name`: a drum, a
    /// keyswitch), by pitch; nothing when it names none, is no CLAP plugin,
    /// or is not made yet. Asked as views are drawn, so it waits for nothing.
    pub(crate) fn device_note_names(&mut self, id: Id) -> BTreeMap<u8, String> {
        let clap = self
            .doc.project
            .device(id)
            .is_some_and(|d| d.kind.starts_with("clap:"));
        let Some(controller) = self
            .live
            .get_mut(&id)
            .and_then(|live| live.controller.as_mut())
            .filter(|_| clap)
        else {
            return BTreeMap::new();
        };
        let names: BTreeMap<String, String> = controller
            .call(paw_engine::device::method::NOTE_NAMES, &[])
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        names
            .into_iter()
            .filter_map(|(key, name)| Some((key.parse::<u8>().ok().filter(|k| *k < 128)?, name)))
            .collect()
    }

    pub(crate) fn device_call(&mut self, id: Id, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        self.flush();
        // A test's command for a device that loads does not wait for it.
        if let Some(answer) = self.load_test(id, method, data) {
            return answer;
        }
        self.await_device(id);
        let kind = &self
            .doc.project
            .device(id)
            .with_context(|| format!("no device {id}"))?
            .kind;
        self.live
            .get_mut(&id)
            .and_then(|live| live.controller.as_mut())
            .with_context(|| format!("device `{kind}` takes no calls"))?
            .call(method, data)
    }

    /// Whether any device needs [`idle`](Self::idle) to be called.
    pub(crate) fn needs_idle(&self) -> bool {
        self.live.values().any(|live| live.controller.is_some())
            || self.loads.busy()
            || self.watching()
            || self.rendering()
            || !self.rec.closing.is_empty()
    }

}

/// What `Session::idle` found among the live devices.
#[derive(Default)]
struct DeviceScan {
    changed: Vec<(Id, Vec<String>)>,
    /// What was moved in a plugin's own window, for writing automation.
    moved: Vec<(Id, String, String, f64)>,
    latency_changed: bool,
    /// Plugins that have stopped working since the last look.
    stopped: Vec<(Id, String)>,
    /// Devices whose output held NaN or infinity, silenced by the engine.
    invalid: Vec<Id>,
    /// Devices that took on a state given to them, and its number.
    applied: Vec<(Id, u64)>,
}
