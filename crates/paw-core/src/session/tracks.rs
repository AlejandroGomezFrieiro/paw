//! Tracks: their fields, order, routing, sends and folders.

use super::*;

impl Session {
    pub fn track_view(&self, id: Id) -> Result<Value> {
        let t = self
            .project
            .track(id)
            .with_context(|| format!("no track {id}"))?;
        let index = self.project.tracks.iter().position(|x| x.id == id);
        Ok(json!({
            "id": t.id, "name": t.name, "volume": t.volume, "pan": t.pan, "mute": t.mute,
            "solo": t.solo, "armed": t.armed, "output": t.output, "sends": t.sends,
            "devices": t.devices.iter().map(|d| d.id).collect::<Vec<_>>(),
            "clips": t.clips.iter().map(|c| c.id).collect::<Vec<_>>(),
            "color": t.color, "meta": t.meta, "index": index.map(|i| i + 1),
            "master": id == MASTER_ID, "input": t.input, "monitor": t.monitor,
            "midi_input": t.midi_input, "midi_output": t.midi_output, "height": t.height,
            "automation": t.automation.name(), "attr_map": t.attr_map,
            // The tracks that devices on this one listen to as side-chains.
            "listens": t.devices.iter().filter_map(|d| d.sidechain).collect::<BTreeSet<_>>(),
            // The tracks that further output pairs of its devices play into.
            "pairs_into": t.devices.iter().flat_map(|d| d.outputs.values()).collect::<BTreeSet<_>>(),
            // A track or a chain read from outside the project's folder, or copied from there.
            "source": t.source, "origin": t.origin,
            "chain_source": t.chain_source, "chain_origin": t.chain_origin,
        }))
    }

    /// One entry of [`track_view`](Self::track_view), made alone: the
    /// handlers of each edit ask for a track's volume or meta, and the whole
    /// view lists every clip of the track.
    pub fn track_field(&self, id: Id, key: &str) -> Result<Value> {
        let t = self
            .project
            .track(id)
            .with_context(|| format!("no track {id}"))?;
        Ok(match key {
            "id" => json!(t.id),
            "name" => json!(t.name),
            "volume" => json!(t.volume),
            "pan" => json!(t.pan),
            "mute" => json!(t.mute),
            "solo" => json!(t.solo),
            "armed" => json!(t.armed),
            "output" => json!(t.output),
            "color" => json!(t.color),
            "meta" => json!(t.meta),
            "master" => json!(id == MASTER_ID),
            "input" => json!(t.input),
            "monitor" => json!(t.monitor),
            "midi_input" => json!(t.midi_input),
            "midi_output" => json!(t.midi_output),
            "height" => json!(t.height),
            _ => self.track_view(id)?.get(key).cloned().unwrap_or(Value::Null),
        })
    }

    pub fn track_add(&mut self, opts: TrackOpts) -> Result<Id> {
        let volume = finite("volume", opts.volume.unwrap_or(0.0))?.clamp(-120.0, 24.0);
        let pan = finite("pan", opts.pan.unwrap_or(0.0))?.clamp(-1.0, 1.0);
        let id = self.new_id();
        self.edit(|p| {
            if let Some(output) = opts.output
                && p.track(output).is_none()
            {
                bail!("no track {output} to output to");
            }
            let mut track = Track::new(id);
            track.name = opts
                .name
                .unwrap_or_else(|| format!("Track {}", p.tracks.len() + 1));
            track.volume = volume;
            track.pan = pan;
            track.output = opts.output.filter(|o| *o != MASTER_ID);
            track.color = opts.color;
            let index = opts
                .index
                .map_or(usize::MAX, |i| i.saturating_sub(1))
                .min(p.tracks.len());
            p.tracks.insert(index, Arc::new(track));
            Ok(id)
        })
    }

    pub fn track_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            if id == MASTER_ID {
                bail!("the master track cannot be removed");
            }
            let index = p
                .tracks
                .iter()
                .position(|t| t.id == id)
                .with_context(|| format!("no track {id}"))?;
            p.tracks.remove(index);
            // Anything that was routed into the removed track falls back to the master.
            for track in &mut p.tracks {
                if track.output == Some(id) || track.sends.iter().any(|s| s.target == id) {
                    let track = Arc::make_mut(track);
                    track.output = track.output.filter(|o| *o != id);
                    track.sends.retain(|s| s.target != id);
                }
            }
            // Devices that listened to it listen to their own input again,
            // and output pairs that played into it are no longer heard.
            let routed = |d: &DeviceInst| {
                d.sidechain == Some(id) || d.outputs.values().any(|to| *to == id)
            };
            for track in std::iter::once(&mut p.master).chain(&mut p.tracks) {
                if track.devices.iter().any(|d| routed(d)) {
                    for device in &mut Arc::make_mut(track).devices {
                        if routed(device) {
                            let device = Arc::make_mut(device);
                            if device.sidechain == Some(id) {
                                device.sidechain = None;
                                device.sidechain_pre = false;
                            }
                            device.outputs.retain(|_, to| *to != id);
                        }
                    }
                }
            }
            Ok(())
        })
    }

    pub fn track_move(&mut self, id: Id, index: usize) -> Result<()> {
        self.edit(|p| {
            let from = p
                .tracks
                .iter()
                .position(|t| t.id == id)
                .with_context(|| format!("no track {id}"))?;
            let track = p.tracks.remove(from);
            p.tracks.insert(index.min(p.tracks.len()), track);
            Ok(())
        })
    }

    pub fn track_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        if holds(&self.track_view(id), key, &value) {
            return Ok(());
        }
        if let (true, Some(track), Some(to)) = (
            matches!(key, "volume" | "pan"),
            self.project.track(id),
            value.as_f64(),
        ) {
            let (target, before) = match key {
                "volume" => (Target::Volume, track.volume),
                _ => (Target::Pan, track.pan),
            };
            self.touch(id, target, before, to);
        }
        let moved = matches!(key, "volume" | "pan").then(|| format!("track {id} {key}"));
        self.edit(|p| {
            if p.track(id).is_none() {
                bail!("no track {id}");
            }
            match key {
                "output" => {
                    let output: Option<Id> = de(key, value)?;
                    let output = output.filter(|o| *o != MASTER_ID);
                    if id == MASTER_ID {
                        bail!("the master track has no output");
                    }
                    if let Some(to) = output {
                        if p.track(to).is_none() {
                            bail!("no track {to} to output to");
                        }
                        if p.would_cycle(id, to) {
                            bail!("routing track {id} into track {to} would make a loop");
                        }
                    }
                    p.track_mut(id).unwrap().output = output;
                }
                "sends" => {
                    let mut sends: Vec<Send> = de(key, value)?;
                    for send in &mut sends {
                        send.level = send.level.clamp(-120.0, 24.0);
                    }
                    for send in &sends {
                        if id == MASTER_ID || p.track(send.target).is_none() {
                            bail!("cannot send from track {id} to track {}", send.target);
                        }
                        if p.would_cycle(id, send.target) {
                            bail!(
                                "sending track {id} to track {} would make a loop",
                                send.target
                            );
                        }
                    }
                    p.track_mut(id).unwrap().sends = sends;
                }
                "input" => {
                    if id == MASTER_ID {
                        bail!("the master track has no input");
                    }
                    let input = match value {
                        Value::Null => None,
                        Value::Number(n) => Some(n.to_string()),
                        Value::String(s) if s.is_empty() || s == "none" => None,
                        Value::String(s) => Some(s),
                        _ => bail!("an input is a channel like \"1\" or a pair like \"1/2\""),
                    };
                    let input = match input {
                        None => None,
                        Some(spec) => match parse_input(&spec) {
                            Some((first, 1)) => Some(format!("{}", first + 1)),
                            Some((first, _)) => Some(format!("{}/{}", first + 1, first + 2)),
                            None => bail!(
                                "bad input `{spec}`: give a channel like \"1\" or a pair like \"1/2\""
                            ),
                        },
                    };
                    p.track_mut(id).unwrap().input = input;
                }
                "midi_input" => {
                    if id == MASTER_ID {
                        bail!("the master track has no input");
                    }
                    let midi = match value {
                        Value::Null => None,
                        Value::String(s) if s == "all" || s.is_empty() => None,
                        Value::String(s) => Some(MidiInput {
                            port: Some(s),
                            channel: None,
                        }),
                        // An empty Lua table arrives as an empty list.
                        Value::Array(a) if a.is_empty() => None,
                        value => {
                            let mut midi: MidiInput = de(key, value)?;
                            if midi.channel.is_some_and(|ch| !(1..=16).contains(&ch)) {
                                bail!("a MIDI channel is from 1 to 16");
                            }
                            if midi.port.as_deref().is_some_and(|p| p.is_empty() || p == "all") {
                                midi.port = None;
                            }
                            (midi != MidiInput::default()).then_some(midi)
                        }
                    };
                    p.track_mut(id).unwrap().midi_input = midi;
                }
                "midi_output" => {
                    let out = midi_out::parse(value)?;
                    p.track_mut(id).unwrap().midi_output = out;
                }
                "attr_map" => p.track_mut(id).unwrap().attr_map = crate::attr_map::parse(value)?,
                _ => {
                    let t = p.track_mut(id).unwrap();
                    match key {
                        "name" => t.name = de(key, value)?,
                        "volume" => t.volume = de::<f64>(key, value)?.clamp(-120.0, 24.0),
                        "pan" => t.pan = de::<f64>(key, value)?.clamp(-1.0, 1.0),
                        "mute" => t.mute = de(key, value)?,
                        "solo" => t.solo = de(key, value)?,
                        "armed" | "monitor" if id == MASTER_ID && de::<bool>(key, value.clone())? => {
                            bail!("the master track records nothing: arm a track")
                        }
                        "armed" => t.armed = de(key, value)?,
                        "monitor" => t.monitor = de(key, value)?,
                        "color" => t.color = de(key, value)?,
                        "meta" => t.meta = de_meta(key, value)?,
                        "automation" => t.automation = de(key, value)?,
                        // A share of the zoom's height, a quarter to eight
                        // times; 1 or nothing is that height.
                        "height" => {
                            t.height = de::<Option<f64>>(key, value)?
                                .filter(|h| h.is_finite() && (h - 1.0).abs() > 1e-9)
                                .map(|h| h.clamp(0.25, 8.0))
                        }
                        _ => bail!("tracks have no settable field `{key}`"),
                    }
                }
            }
            Ok(())
        })?;
        if let Some(name) = moved {
            self.swept(name);
        }
        Ok(())
    }
}
