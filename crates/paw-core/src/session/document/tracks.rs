//! Tracks: their fields, order, routing, sends and folders.

use std::collections::BTreeSet;
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

use super::Document;
use crate::model::{DeviceInst, Id, InputChannels, MASTER_ID, MidiInput, Project, Send, Target, Track};
use crate::session::{TrackListOpts, TrackOpts, de, de_meta, finite, holds, midi_out};

/// A fader or pan knob that [`Document::track_set`] moved: where it was and
/// where it went.
#[derive(Clone, Debug, PartialEq)]
pub struct ControlMove {
    pub target: Target,
    pub before: f64,
    pub to: f64,
}

impl Document {
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
            // The subproject the track belongs to; nil for the song's.
            "nest": t.nest,
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
            "nest" => json!(t.nest),
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
            if let Some(nest) = opts.nest
                && p.nest(nest).is_none()
            {
                bail!("no subproject {nest} to add a track to");
            }
            if let Some(output) = opts.output.filter(|o| *o != MASTER_ID) {
                let Some(to) = p.track(output) else {
                    bail!("no track {output} to output to");
                };
                if to.nest != opts.nest {
                    bail!("track {output} ({}) is not in the same subproject: the tracks of a subproject route only to each other", to.name);
                }
            }
            let mut track = Track::new(id);
            track.nest = opts.nest;
            // Numbered among the tracks of the song, or of its nest.
            let masters: BTreeSet<Id> = p.nests.values().map(|n| n.master).collect();
            let count = p
                .tracks
                .iter()
                .filter(|t| t.nest == opts.nest && !masters.contains(&t.id))
                .count();
            track.name = opts.name.unwrap_or_else(|| format!("Track {}", count + 1));
            track.volume = volume;
            track.pan = pan;
            track.output = opts.output.filter(|o| *o != MASTER_ID);
            track.color = opts.color;
            let index = opts.index.map_or(usize::MAX, |i| i.saturating_sub(1));
            let at = p.place_position(opts.nest, index);
            p.tracks.insert(at, Arc::new(track));
            Ok(id)
        })
    }

    pub fn track_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            if id == MASTER_ID {
                bail!("the master track cannot be removed");
            }
            if let Some(nest) = p.nests.values().find(|n| n.master == id) {
                bail!("track {id} is the master of the subproject {}: it cannot be removed", nest.name);
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

    /// The ids of the tracks of the song, of one subproject (`nest`), or
    /// of both (`all`), in their order.
    pub fn track_ids(&self, opts: &TrackListOpts) -> Vec<Id> {
        if opts.all {
            return self.project.tracks.iter().map(|t| t.id).collect();
        }
        self.project.place_tracks(opts.nest).map(|t| t.id).collect()
    }

    /// Move a track to `index` (from 0) among the tracks of its place: the
    /// song, or its subproject.
    pub fn track_move(&mut self, id: Id, index: usize) -> Result<()> {
        self.edit(|p| {
            let from = p
                .tracks
                .iter()
                .position(|t| t.id == id)
                .with_context(|| format!("no track {id}"))?;
            let track = p.tracks.remove(from);
            let at = p.place_position(track.nest, index);
            p.tracks.insert(at, track);
            Ok(())
        })
    }

    /// Set `key` of track `id` to `value`. A value that the track already
    /// holds is no change. Gives the fader or pan knob that the edit moved,
    /// for the session to write as automation while the song plays.
    pub fn track_set(&mut self, id: Id, key: &str, value: Value) -> Result<Option<ControlMove>> {
        if holds(&self.track_view(id), key, &value) {
            return Ok(None);
        }
        // An unknown key fails inside the edit, after a missing track does.
        let field = key.parse::<TrackField>();
        let moved = matches!(field, Ok(TrackField::Volume | TrackField::Pan));
        let control = match (moved, self.project.track(id), value.as_f64()) {
            (true, Some(track), Some(to)) => Some(match field {
                Ok(TrackField::Volume) => ControlMove { target: Target::Volume, before: track.volume, to },
                _ => ControlMove { target: Target::Pan, before: track.pan, to },
            }),
            _ => None,
        };
        self.edit(|p| {
            if p.track(id).is_none() {
                bail!("no track {id}");
            }
            field?.set(p, id, key, value)
        })?;
        if moved {
            self.swept(format!("track {id} {key}"));
        }
        Ok(control)
    }

    /// Make every track read from a folder outside the project, and every
    /// chain read from a file outside it, the project's own (`:collect`):
    /// the next save writes them into its folder. Returns how many tracks
    /// and how many chains. Run before `clip_collect`, which then takes
    /// such a track's clips.
    pub fn track_collect(&mut self) -> (usize, usize) {
        let (mut tracks, mut chains) = (0, 0);
        for track in &mut self.project.tracks {
            if track.source.is_none() && track.chain_source.is_none() {
                continue;
            }
            let track = Arc::make_mut(track);
            if track.source.is_some() {
                track.origin = track.source.take();
                tracks += 1;
            }
            if track.chain_source.is_some() {
                track.chain_origin = track.chain_source.take();
                chains += 1;
            }
        }
        if tracks + chains > 0 {
            self.undo.touched = true;
            self.dirty = true;
        }
        (tracks, chains)
    }

    /// The milliseconds a note with `attr` is moved by the track's attribute map.
    pub fn attr_delay(&self, track: Id, attr: paw_engine::Attr) -> Result<f64> {
        let track = self
            .project
            .track(track)
            .with_context(|| format!("no track {track}"))?;
        Ok(match &track.attr_map {
            Some(map) => map.plan()?.delay_of(attr),
            None => 0.0,
        })
    }
}

/// A field of a track that [`Document::track_set`] changes: the key that Lua
/// gives, parsed once.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TrackField {
    Name,
    Volume,
    Pan,
    Mute,
    Solo,
    Armed,
    Monitor,
    Color,
    Meta,
    Automation,
    Height,
    Output,
    Sends,
    Input,
    MidiInput,
    MidiOutput,
    AttrMap,
}

impl TrackField {
    /// Set this field of track `id`, which is in `p`. `key` is the field's
    /// key in Lua, for the error texts.
    fn set(self, p: &mut Project, id: Id, key: &str, value: Value) -> Result<()> {
        match self {
            // Routing looks at the other tracks before it changes this one.
            Self::Output => {
                let output = checked_output(p, id, de(key, value)?)?;
                track_in(p, id)?.output = output;
            }
            Self::Sends => {
                let sends = checked_sends(p, id, de(key, value)?)?;
                track_in(p, id)?.sends = sends;
            }
            own => own.set_own(track_in(p, id)?, id, key, value)?,
        }
        Ok(())
    }

    /// Set a field that only the track's own state decides.
    fn set_own(self, t: &mut Track, id: Id, key: &str, value: Value) -> Result<()> {
        match self {
            Self::Name => t.name = de(key, value)?,
            Self::Volume => t.volume = de::<f64>(key, value)?.clamp(-120.0, 24.0),
            Self::Pan => t.pan = de::<f64>(key, value)?.clamp(-1.0, 1.0),
            Self::Mute => t.mute = de(key, value)?,
            Self::Solo => t.solo = de(key, value)?,
            Self::Armed | Self::Monitor => {
                let on: bool = de(key, value)?;
                if on && id == MASTER_ID {
                    bail!("the master track records nothing: arm a track");
                }
                if self == Self::Armed {
                    t.armed = on;
                } else {
                    t.monitor = on;
                }
            }
            Self::Color => t.color = de(key, value)?,
            Self::Meta => t.meta = de_meta(key, value)?,
            Self::Automation => t.automation = de(key, value)?,
            // A share of the zoom's height, a quarter to eight times; 1 or
            // nothing is that height.
            Self::Height => {
                t.height = de::<Option<f64>>(key, value)?
                    .filter(|h| h.is_finite() && (h - 1.0).abs() > 1e-9)
                    .map(|h| h.clamp(0.25, 8.0));
            }
            Self::Input => {
                if id == MASTER_ID {
                    bail!("the master track has no input");
                }
                t.input = input_of(value)?;
            }
            Self::MidiInput => {
                if id == MASTER_ID {
                    bail!("the master track has no input");
                }
                t.midi_input = midi_input_of(value)?;
            }
            Self::MidiOutput => t.midi_output = midi_out::parse(value)?,
            Self::AttrMap => t.attr_map = crate::attr_map::parse(value)?,
            Self::Output | Self::Sends => unreachable!("`set` sets the routing"),
        }
        Ok(())
    }
}

impl std::str::FromStr for TrackField {
    type Err = anyhow::Error;

    fn from_str(key: &str) -> Result<Self> {
        Ok(match key {
            "name" => Self::Name,
            "volume" => Self::Volume,
            "pan" => Self::Pan,
            "mute" => Self::Mute,
            "solo" => Self::Solo,
            "armed" => Self::Armed,
            "monitor" => Self::Monitor,
            "color" => Self::Color,
            "meta" => Self::Meta,
            "automation" => Self::Automation,
            "height" => Self::Height,
            "output" => Self::Output,
            "sends" => Self::Sends,
            "input" => Self::Input,
            "midi_input" => Self::MidiInput,
            "midi_output" => Self::MidiOutput,
            "attr_map" => Self::AttrMap,
            _ => bail!("tracks have no settable field `{key}`"),
        })
    }
}

fn track_in(p: &mut Project, id: Id) -> Result<&mut Track> {
    p.track_mut(id).with_context(|| format!("no track {id}"))
}

/// Where track `id` may output to: `None` is the master.
fn checked_output(p: &Project, id: Id, output: Option<Id>) -> Result<Option<Id>> {
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
        p.check_route(id, to, crate::model::Route::Output)?;
    }
    Ok(output)
}

/// The sends that track `id` may have, their levels clamped.
fn checked_sends(p: &Project, id: Id, mut sends: Vec<Send>) -> Result<Vec<Send>> {
    for send in &mut sends {
        send.level = send.level.clamp(-120.0, 24.0);
    }
    for send in &sends {
        if id == MASTER_ID || p.track(send.target).is_none() {
            bail!("cannot send from track {id} to track {}", send.target);
        }
        if p.would_cycle(id, send.target) {
            bail!("sending track {id} to track {} would make a loop", send.target);
        }
        p.check_route(id, send.target, crate::model::Route::Send)?;
    }
    Ok(sends)
}

/// An audio input from Lua: a channel like "1", a pair like "1/2", or none.
fn input_of(value: Value) -> Result<Option<InputChannels>> {
    let spec = match value {
        Value::Null => return Ok(None),
        Value::Number(n) => n.to_string(),
        Value::String(s) if s.is_empty() || s == "none" => return Ok(None),
        Value::String(s) => s,
        _ => bail!("an input is a channel like \"1\" or a pair like \"1/2\""),
    };
    spec.parse().map(Some).map_err(|e: String| anyhow::anyhow!(e))
}

/// A MIDI input from Lua: a port's name, a `{port, channel}` table, or all.
fn midi_input_of(value: Value) -> Result<Option<MidiInput>> {
    Ok(match value {
        Value::Null => None,
        Value::String(s) if s == "all" || s.is_empty() => None,
        Value::String(s) => Some(MidiInput {
            port: Some(s),
            channel: None,
        }),
        // An empty Lua table arrives as an empty list.
        Value::Array(a) if a.is_empty() => None,
        value => {
            let mut midi: MidiInput = de("midi_input", value)?;
            if midi.channel.is_some_and(|ch| !(1..=16).contains(&ch)) {
                bail!("a MIDI channel is from 1 to 16");
            }
            if midi.port.as_deref().is_some_and(|p| p.is_empty() || p == "all") {
                midi.port = None;
            }
            (midi != MidiInput::default()).then_some(midi)
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A document with one track, at volume 0 dB.
    fn one_track() -> (Document, Id) {
        let mut doc = Document::default();
        let id = doc.track_add(TrackOpts::default()).unwrap();
        (doc, id)
    }

    #[test]
    fn a_set_gives_the_fader_or_pan_knob_it_moved() {
        let cases = [
            ("volume", json!(-6.0), Some(ControlMove { target: Target::Volume, before: 0.0, to: -6.0 })),
            ("pan", json!(0.5), Some(ControlMove { target: Target::Pan, before: 0.0, to: 0.5 })),
            ("volume", json!(0), None),
            ("name", json!("Bass"), None),
        ];
        for (key, value, want) in cases {
            let (mut doc, id) = one_track();
            let moved = doc.track_set(id, key, value.clone()).unwrap();
            assert_eq!(moved, want, "{key} set to {value}");
        }
    }
}
