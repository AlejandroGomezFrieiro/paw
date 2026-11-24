//! Parts: their fields, order, routing, sends and folders.

use std::collections::BTreeSet;
use std::path::Path;
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde_json::{Map, Value};

use super::Document;
use super::values::{Given, Lazy, NoTable, finite, patch, view};
use crate::attr_map::AttrMap;
use crate::model::kinds::{KindId, PartFamily};
use crate::model::{
    AutoMode, Clips, DeviceInst, Id, InputChannels, MASTER_ID, MidiInput, MidiOutput, NestId, OutForm, Part,
    Project, Send, Target,
};

/// What `paw.api.part_add` takes for a new part.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct PartOpts {
    pub name: Option<String>,
    /// Position among the parts of its place (the song, or its
    /// subproject), counting from 1. Appended when absent.
    pub index: Option<usize>,
    pub volume: Option<f64>,
    pub pan: Option<f64>,
    pub output: Option<Id>,
    pub color: Option<String>,
    /// The nest (subproject) the part is made in; the song when absent.
    pub nest: Option<NestId>,
}

/// What `paw.api.part_list` takes: the parts of the song when empty.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct PartListOpts {
    /// The parts of this subproject, without its master.
    pub nest: Option<NestId>,
    /// Every part: the song's and those of each subproject.
    pub all: bool,
}

/// A fader or pan knob that [`Document::part_set`] moved: where it was and
/// where it went.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct ControlMove {
    pub target: Target,
    pub before: f64,
    pub to: f64,
}

view! {
    /// `paw.api.part_get(id)`. `volume` in dB, `pan` -1 to 1, `output` the
    /// part it feeds (nil for the master), `index` from 1 among all parts.
    /// `devices` and `clips` are ids.
    #[schemars(rename = "Part")]
    pub(crate) struct PartView<'a> {
        id: Id,
        name: &'a str,
        volume: f64,
        pan: f64,
        mute: bool,
        solo: bool,
        armed: bool,
        output: Option<Id>,
        sends: &'a [Send],
        devices: DeviceIds<'a>,
        clips: ClipIds<'a>,
        color: Option<&'a str>,
        #[schemars(extend("x-teal" = "Meta"))]
        meta: &'a Map<String, Value>,
        index: Lazy<(&'a Project, Id), Option<usize>>,
        master: bool,
        #[schemars(with = "Option<String>")]
        input: Option<InputChannels>,
        monitor: bool,
        midi_input: Option<&'a MidiInput>,
        midi_output: Option<&'a MidiOutput>,
        height: Option<f64>,
        automation: AutoMode,
        #[schemars(with = "Option<Value>", extend("x-teal" = "AttrMap"))]
        attr_map: Option<&'a AttrMap>,
        /// The parts that devices on this one listen to as side-chains.
        listens: Lazy<&'a Part, BTreeSet<Id>>,
        /// The parts that further output pairs of its devices play into.
        pairs_into: Lazy<&'a Part, BTreeSet<Id>>,
        /// A part read from a part folder outside the project's folder.
        source: Option<&'a Path>,
        /// The part folder outside the project that the part was copied from.
        origin: Option<&'a Path>,
        /// A chain read from a chain file outside the project's folder.
        chain_source: Option<&'a Path>,
        /// The chain file outside the project that the chain was copied from.
        chain_origin: Option<&'a Path>,
        /// The subproject that the part belongs to; nil for the song's.
        nest: Option<NestId>,
        /// The kind of the part (`paw.kinds.define("part", ...)`); nil for
        /// an ordinary part.
        #[schemars(with = "Option<String>")]
        kind: Option<&'a KindId<PartFamily>>,
        /// The group that the part is in; nil at the top level.
        parent: Option<Id>,
    }
}

/// The ids of a part's devices, written as a list with no copy.
struct DeviceIds<'a>(&'a [Arc<DeviceInst>]);

impl serde::Serialize for DeviceIds<'_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error> {
        serializer.collect_seq(self.0.iter().map(|d| d.id))
    }
}

impl schemars::JsonSchema for DeviceIds<'_> {
    fn inline_schema() -> bool {
        true
    }

    fn schema_name() -> std::borrow::Cow<'static, str> {
        "DeviceIds".into()
    }

    fn json_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
        Vec::<Id>::json_schema(generator)
    }
}

/// The ids of a part's clips, written as a list with no copy: the view of
/// one field does not go through every clip.
struct ClipIds<'a>(&'a Clips);

impl serde::Serialize for ClipIds<'_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error> {
        serializer.collect_seq(self.0.iter().map(|c| c.id))
    }
}

impl schemars::JsonSchema for ClipIds<'_> {
    fn inline_schema() -> bool {
        true
    }

    fn schema_name() -> std::borrow::Cow<'static, str> {
        "ClipIds".into()
    }

    fn json_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
        Vec::<Id>::json_schema(generator)
    }
}

impl<'a> PartView<'a> {
    /// The view of part `t` of project `p`.
    fn of(p: &'a Project, t: &'a Part) -> Self {
        Self {
            id: t.id,
            name: &t.name,
            volume: t.volume,
            pan: t.pan,
            mute: t.mute,
            solo: t.solo,
            armed: t.armed,
            output: t.output,
            sends: &t.sends,
            devices: DeviceIds(&t.devices),
            clips: ClipIds(&t.clips),
            color: t.color.as_deref(),
            meta: &t.meta,
            index: Lazy::new((p, t.id), |(p, id)| p.parts.iter().position(|x| x.id == *id).map(|i| i + 1)),
            master: t.id == MASTER_ID,
            input: t.input,
            monitor: t.monitor,
            midi_input: t.midi_input.as_ref(),
            midi_output: t.midi_output.as_ref(),
            height: t.height,
            automation: t.automation,
            attr_map: t.attr_map.as_ref(),
            listens: Lazy::new(t, |t| t.devices.iter().filter_map(|d| d.sidechain).collect()),
            pairs_into: Lazy::new(t, |t| t.devices.iter().flat_map(|d| d.outputs.values().copied()).collect()),
            source: t.source.as_deref(),
            origin: t.origin.as_deref(),
            chain_source: t.chain_source.as_deref(),
            chain_origin: t.chain_origin.as_deref(),
            nest: t.nest,
            kind: t.kind.as_ref(),
            parent: t.parent,
        }
    }
}

impl Document {
    /// Part `id` as `paw.api.part_get` gives it.
    pub(crate) fn part_view(&self, id: Id) -> Result<PartView<'_>> {
        let t = self.project.part(id).with_context(|| format!("no part {id}"))?;
        Ok(PartView::of(&self.project, t))
    }

    pub(crate) fn part_add(&mut self, opts: PartOpts) -> Result<Id> {
        let volume = finite("volume", opts.volume.unwrap_or(0.0))?.clamp(-120.0, 24.0);
        let pan = finite("pan", opts.pan.unwrap_or(0.0))?.clamp(-1.0, 1.0);
        let id = self.new_id();
        self.edit(|p| {
            if let Some(nest) = opts.nest
                && p.nest(nest).is_none()
            {
                bail!("no subproject {nest} to add a part to");
            }
            if let Some(output) = opts.output.filter(|o| *o != MASTER_ID) {
                let Some(to) = p.part(output) else {
                    bail!("no part {output} to output to");
                };
                if to.nest != opts.nest {
                    bail!("part {output} ({}) is not in the same subproject: the parts of a subproject route only to each other", to.name);
                }
            }
            let mut part = Part::new(id);
            part.nest = opts.nest;
            // Numbered among the parts of the song, or of its nest.
            let masters: BTreeSet<Id> = p.nests.values().map(|n| n.master).collect();
            let count = p
                .parts
                .iter()
                .filter(|t| t.nest == opts.nest && !masters.contains(&t.id))
                .count();
            part.name = opts.name.unwrap_or_else(|| format!("Part {}", count + 1));
            part.volume = volume;
            part.pan = pan;
            part.output = opts.output.filter(|o| *o != MASTER_ID);
            part.color = opts.color;
            let index = opts.index.map_or(usize::MAX, |i| i.saturating_sub(1));
            let at = p.place_position(opts.nest, index);
            p.parts.insert(at, Arc::new(part));
            Ok(id)
        })
    }

    pub(crate) fn part_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            if id == MASTER_ID {
                bail!("the master part cannot be removed");
            }
            if let Some(nest) = p.nests.values().find(|n| n.master == id) {
                bail!("part {id} is the master of the subproject {}: it cannot be removed", nest.name);
            }
            let index = p
                .parts
                .iter()
                .position(|t| t.id == id)
                .with_context(|| format!("no part {id}"))?;
            p.parts.remove(index);
            // Anything that was routed into the removed part falls back to
            // the master, and the members of a removed group stand at the
            // top level.
            for part in &mut p.parts {
                if part.output == Some(id) || part.parent == Some(id) || part.sends.iter().any(|s| s.target == id) {
                    let part = Arc::make_mut(part);
                    part.output = part.output.filter(|o| *o != id);
                    part.parent = part.parent.filter(|g| *g != id);
                    part.sends.retain(|s| s.target != id);
                }
            }
            // Devices that listened to it listen to their own input again,
            // and output pairs that played into it are no longer heard.
            let routed = |d: &DeviceInst| {
                d.sidechain == Some(id) || d.outputs.values().any(|to| *to == id)
            };
            for part in std::iter::once(&mut p.master).chain(&mut p.parts) {
                if part.devices.iter().any(|d| routed(d)) {
                    for device in &mut Arc::make_mut(part).devices {
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

    /// The ids of the parts of the song, of one subproject (`nest`), or
    /// of both (`all`), in their order.
    pub(crate) fn part_ids(&self, opts: &PartListOpts) -> Vec<Id> {
        if opts.all {
            return self.project.parts.iter().map(|t| t.id).collect();
        }
        self.project.place_parts(opts.nest).map(|t| t.id).collect()
    }

    /// Move a part to `index` (from 0) among the parts of its place: the
    /// song, or its subproject.
    pub(crate) fn part_move(&mut self, id: Id, index: usize) -> Result<()> {
        self.edit(|p| {
            let from = p
                .parts
                .iter()
                .position(|t| t.id == id)
                .with_context(|| format!("no part {id}"))?;
            let part = p.parts.remove(from);
            let at = p.place_position(part.nest, index);
            p.parts.insert(at, part);
            Ok(())
        })
    }

    /// Make one change of part `id`. A value that the part already holds is
    /// no change. Gives the fader or pan knob that the edit moved, for the
    /// session to write as automation while the song plays.
    pub(crate) fn part_set(&mut self, id: Id, change: PartChange) -> Result<Option<ControlMove>> {
        let part = self.project.part(id).with_context(|| format!("no part {id}"))?;
        if change.holds(part) {
            return Ok(None);
        }
        let control = match change {
            PartChange::Volume(to) => Some(ControlMove { target: Target::Volume, before: part.volume, to }),
            PartChange::Pan(to) => Some(ControlMove { target: Target::Pan, before: part.pan, to }),
            _ => None,
        };
        let key = control.as_ref().map(|_| super::values::Change::key(&change));
        self.edit(|p| change.set(p, id))?;
        if let Some(key) = key {
            self.swept(format!("part {id} {key}"));
        }
        Ok(control)
    }

    /// Make every part read from a folder outside the project, and every
    /// chain read from a file outside it, the project's own (`:collect`):
    /// the next save writes them into its folder. Returns how many parts
    /// and how many chains. Run before `clip_collect`, which then takes
    /// such a part's clips.
    pub(crate) fn part_collect(&mut self) -> (usize, usize) {
        let (mut parts, mut chains) = (0, 0);
        for part in &mut self.project.parts {
            if part.source.is_none() && part.chain_source.is_none() {
                continue;
            }
            let part = Arc::make_mut(part);
            if part.source.is_some() {
                part.origin = part.source.take();
                parts += 1;
            }
            if part.chain_source.is_some() {
                part.chain_origin = part.chain_source.take();
                chains += 1;
            }
        }
        if parts + chains > 0 {
            self.undo.touched = true;
            self.dirty = true;
        }
        (parts, chains)
    }

    /// The milliseconds a note with `attr` is moved by the part's attribute map.
    pub(crate) fn attr_delay(&self, part: Id, attr: paw_types::Attr) -> Result<f64> {
        let part = self
            .project
            .part(part)
            .with_context(|| format!("no part {part}"))?;
        Ok(match &part.attr_map {
            Some(map) => map.plan()?.delay_of(attr),
            None => 0.0,
        })
    }
}

patch! {
    /// What `paw.api.part_set` changes in a part: each field as `part_get`
    /// gives it, and what is left out stays. Nil clears a field that can be
    /// empty (`part_set(id, "output", nil)`), and is refused for the others.
    #[schemars(rename = "PartChanges")]
    pub(crate) struct PartPatch => PartChange, "parts have no settable field" {
        /// The part records when the song records.
        "armed" armed: bool => Armed value,
        /// How the MIDI 2.0 attributes of its notes reach an instrument that
        /// does not take them. Nil, false or an empty table for none.
        #[schemars(with = "Option<Value>", extend("x-teal" = "AttrMap"))]
        "attr_map" attr_map: Given<AttrMap> => AttrMap clear,
        /// What a move of a control does to the part's automation while the
        /// song plays.
        "automation" automation: AutoMode => Automation value,
        "color" color: String => Color clear,
        /// A share of the height of every part, from a quarter to eight
        /// times; nil or 1 for that height.
        "height" height: f64 => Height clear,
        /// An audio input: a channel such as "1", a pair such as "1/2", or
        /// nil or "none" for none.
        #[schemars(with = "Option<String>", extend("x-teal" = "string | integer"))]
        "input" input: Given<NoTable> => Input clear,
        /// The kind of the part: the name of a part kind, or nil for an
        /// ordinary part. A kind that no extension defines is kept.
        #[schemars(with = "Option<String>")]
        "kind" kind: KindId<PartFamily> => Kind clear,
        #[schemars(extend("x-teal" = "Meta"))]
        "meta" meta: Map<String, Value> => Meta default,
        /// The MIDI the part plays when armed: a port's name, a table of
        /// `port` and `channel`, or nil or "all" for every port.
        #[schemars(with = "Option<MidiInput>", extend("x-teal" = "string | MidiInput"))]
        "midi_input" midi_input: Given<MidiInput> => MidiInput clear,
        /// Where the part sends MIDI: a port's name, a table of `port`,
        /// `channel`, `form` and `members`, or nil or "none" for none.
        #[schemars(with = "Option<MidiOutput>", extend("x-teal" = "string | MidiOutput"))]
        "midi_output" midi_output: Given<MidiOutputGiven> => MidiOutput clear,
        /// Hear the input even when the part is not armed.
        "monitor" monitor: bool => Monitor value,
        "mute" mute: bool => Mute value,
        "name" name: String => Name value,
        /// The part it feeds; nil for the master.
        "output" output: Id => Output clear,
        /// From -1 (left) to 1 (right).
        "pan" pan: f64 => Pan value,
        /// The group that the part is in, or nil for the top level. A group
        /// cannot be put inside itself.
        "parent" parent: Id => Parent clear,
        /// Its sends, each with a `level` in dB.
        "sends" sends: Vec<Send> => Sends value,
        "solo" solo: bool => Solo value,
        /// The fader in dB, from -120 to 24.
        "volume" volume: f64 => Volume value,
    }
}

/// A MIDI output as a script gives it in a table: the port can be left
/// out of an empty table only.
#[derive(Clone, Debug, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct MidiOutputGiven {
    #[serde(default)]
    port: String,
    #[serde(default)]
    channel: Option<u8>,
    #[serde(default)]
    form: OutForm,
    #[serde(default)]
    members: Option<u8>,
}

impl PartChange {
    /// Part `t` already holds what the change gives: setting it would
    /// change nothing, and makes no undo step. A value that does not read
    /// is never held: setting it gives its error.
    #[expect(clippy::float_cmp, reason = "an unchanged value makes no undo step")]
    fn holds(&self, t: &Part) -> bool {
        match self {
            Self::Armed(on) => t.armed == *on,
            Self::Automation(mode) => t.automation == *mode,
            Self::Color(color) => t.color == *color,
            Self::Height(height) => t.height == *height,
            Self::Kind(kind) => t.kind == *kind,
            Self::Parent(parent) => t.parent == *parent,
            Self::Meta(meta) => t.meta == *meta,
            Self::Monitor(on) => t.monitor == *on,
            Self::Mute(on) => t.mute == *on,
            Self::Name(name) => t.name == *name,
            Self::Output(output) => t.output == *output,
            Self::Pan(pan) => t.pan == *pan,
            Self::Sends(sends) => t.sends == *sends,
            Self::Solo(on) => t.solo == *on,
            Self::Volume(volume) => t.volume == *volume,
            Self::Input(given) => input_of(given.clone()).is_ok_and(|input| t.input == input),
            Self::MidiInput(given) => midi_input_of(given.clone()).is_ok_and(|midi| t.midi_input == midi),
            Self::MidiOutput(given) => midi_output_of(given.clone()).is_ok_and(|midi| t.midi_output == midi),
            Self::AttrMap(given) => attr_map_of(given.clone()).is_ok_and(|map| t.attr_map == map),
        }
    }

    /// Make the change to part `id`, which is in `p`.
    fn set(self, p: &mut Project, id: Id) -> Result<()> {
        // Routing looks at the other parts before it changes this one.
        let change = match self {
            Self::Output(output) => Self::Output(checked_output(p, id, output)?),
            Self::Sends(sends) => Self::Sends(checked_sends(p, id, sends)?),
            Self::Parent(parent) => Self::Parent(checked_parent(p, id, parent)?),
            own => own,
        };
        let t = p.part_in(id)?;
        match change {
            Self::Output(output) => t.output = output,
            Self::Sends(sends) => t.sends = sends,
            Self::Name(name) => t.name = name,
            Self::Volume(volume) => t.volume = finite("volume", volume)?.clamp(-120.0, 24.0),
            Self::Pan(pan) => t.pan = finite("pan", pan)?.clamp(-1.0, 1.0),
            Self::Mute(on) => t.mute = on,
            Self::Solo(on) => t.solo = on,
            Self::Armed(on) => t.armed = check_records(id, on)?,
            Self::Monitor(on) => t.monitor = check_records(id, on)?,
            Self::Color(color) => t.color = color,
            Self::Meta(meta) => t.meta = meta,
            Self::Kind(kind) => t.kind = kind,
            Self::Parent(parent) => t.parent = parent,
            Self::Automation(mode) => t.automation = mode,
            // A share of the zoom's height, a quarter to eight times; 1 or
            // nothing is that height.
            Self::Height(height) => {
                t.height = height
                    .filter(|h| h.is_finite() && (h - 1.0).abs() > 1e-9)
                    .map(|h| h.clamp(0.25, 8.0));
            }
            Self::Input(given) => t.input = check_input(id, input_of(given)?)?,
            Self::MidiInput(given) => t.midi_input = check_input(id, midi_input_of(given)?)?,
            Self::MidiOutput(given) => t.midi_output = midi_output_of(given)?,
            Self::AttrMap(given) => t.attr_map = attr_map_of(given)?,
        }
        Ok(())
    }
}

/// `on` for a switch of recording (`armed`, `monitor`): the master part
/// records nothing.
fn check_records(id: Id, on: bool) -> Result<bool> {
    if on && id == MASTER_ID {
        bail!("the master part records nothing: arm a part");
    }
    Ok(on)
}

/// An input for part `id`: the master part has none.
fn check_input<T>(id: Id, input: Option<T>) -> Result<Option<T>> {
    if id == MASTER_ID {
        bail!("the master part has no input");
    }
    Ok(input)
}


/// Where part `id` may output to: `None` is the master.
fn checked_output(p: &Project, id: Id, output: Option<Id>) -> Result<Option<Id>> {
    let output = output.filter(|o| *o != MASTER_ID);
    if id == MASTER_ID {
        bail!("the master part has no output");
    }
    if let Some(to) = output {
        if p.part(to).is_none() {
            bail!("no part {to} to output to");
        }
        if p.would_cycle(id, to) {
            bail!("routing part {id} into part {to} would make a loop");
        }
        p.check_route(id, to, crate::model::Route::Output)?;
    }
    Ok(output)
}

/// The group that part `id` may go into: a part of its place that is not
/// the part itself nor a part inside it. Groups nest to any depth.
fn checked_parent(p: &Project, id: Id, parent: Option<Id>) -> Result<Option<Id>> {
    let Some(group) = parent else { return Ok(None) };
    if id == MASTER_ID || group == MASTER_ID {
        bail!("the master part is in no group and holds none");
    }
    let part = p.part(id).with_context(|| format!("no part {id}"))?;
    let holder = p.part(group).with_context(|| format!("no part {group} to put part {id} in"))?;
    if holder.nest != part.nest {
        bail!("part {group} is in another subproject than part {id}");
    }
    // Walk up from the new group: meeting the part itself means the part
    // would hold its own group. The walk stops at a cycle that a file
    // brought in, so it ends on any project.
    let mut seen = BTreeSet::new();
    let mut at = Some(group);
    while let Some(now) = at {
        if now == id {
            bail!("`{}` cannot go into `{}`: it holds that group", part.name, holder.name);
        }
        if !seen.insert(now) {
            break;
        }
        at = p.part(now).and_then(|t| t.parent);
    }
    Ok(Some(group))
}

/// The sends that part `id` may have, their levels clamped.
fn checked_sends(p: &Project, id: Id, mut sends: Vec<Send>) -> Result<Vec<Send>> {
    for send in &mut sends {
        send.level = send.level.clamp(-120.0, 24.0);
    }
    for send in &sends {
        if id == MASTER_ID || p.part(send.target).is_none() {
            bail!("cannot send from part {id} to part {}", send.target);
        }
        if p.would_cycle(id, send.target) {
            bail!("sending part {id} to part {} would make a loop", send.target);
        }
        p.check_route(id, send.target, crate::model::Route::Send)?;
    }
    Ok(sends)
}

/// An audio input as a script gives it: a channel like "1" or 1, a pair
/// like "1/2", or none.
fn input_of(given: Option<Given<NoTable>>) -> Result<Option<InputChannels>> {
    let spec = match given {
        None | Some(Given::Empty) => return Ok(None),
        Some(Given::Number(n)) => n.to_string(),
        Some(Given::Word(word)) if word.is_empty() || word == "none" => return Ok(None),
        Some(Given::Word(word)) => word,
        Some(Given::Flag(_)) => bail!("an input is a channel like \"1\" or a pair like \"1/2\""),
        Some(Given::Table(never)) => match never {},
    };
    spec.parse().map(Some).map_err(|e: String| anyhow::anyhow!(e))
}

/// A MIDI input as a script gives it: a port's name, a `{port, channel}`
/// table, or all.
fn midi_input_of(given: Option<Given<MidiInput>>) -> Result<Option<MidiInput>> {
    Ok(match given {
        None | Some(Given::Empty) => None,
        Some(Given::Word(word)) if word == "all" || word.is_empty() => None,
        Some(Given::Word(port)) => Some(MidiInput { port: Some(port), channel: None }),
        Some(Given::Number(_) | Given::Flag(_)) => bail!("a MIDI input is a port's name or a table of `port` and `channel`"),
        Some(Given::Table(mut midi)) => {
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

/// A part's MIDI output as a script gives it: a port's name, a table
/// `{ port, channel, form, members }`, or nil (or "none") for none.
fn midi_output_of(given: Option<Given<MidiOutputGiven>>) -> Result<Option<MidiOutput>> {
    let out = match given {
        None | Some(Given::Empty) => return Ok(None),
        Some(Given::Word(word)) if word.is_empty() || word == "none" => return Ok(None),
        Some(Given::Word(port)) => MidiOutput { port, channel: None, form: OutForm::default(), members: None },
        Some(Given::Number(_) | Given::Flag(_)) => bail!("a MIDI output is a port's name or a table of `port` and `channel`"),
        Some(Given::Table(table)) => MidiOutput {
            port: table.port,
            channel: table.channel,
            form: table.form,
            members: table.members,
        },
    };
    if out.port.is_empty() {
        bail!("a MIDI output needs a port: one of paw.midi.outputs()");
    }
    if out.channel.is_some_and(|ch| !(1..=16).contains(&ch)) {
        bail!("a MIDI channel is from 1 to 16");
    }
    if out.members.is_some_and(|n| !(1..=15).contains(&n)) {
        bail!("an MPE zone has 1 to 15 member channels");
    }
    Ok(Some(out))
}

/// A part's attribute map as a script gives it: a table, or nil, false or
/// an empty table for none.
fn attr_map_of(given: Option<Given<AttrMap>>) -> Result<Option<AttrMap>> {
    match given {
        None | Some(Given::Empty | Given::Flag(false)) => Ok(None),
        Some(Given::Table(map)) => {
            map.plan()?;
            Ok(Some(map))
        }
        Some(Given::Word(_) | Given::Number(_) | Given::Flag(true)) => bail!("an attr_map is a table"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A document with one part, at volume 0 dB.
    fn one_part() -> (Document, Id) {
        let mut doc = Document::default();
        let id = doc.part_add(PartOpts::default()).unwrap();
        (doc, id)
    }

    #[test]
    fn a_set_gives_the_fader_or_pan_knob_it_moved() {
        let cases = [
            (PartChange::Volume(-6.0), Some(ControlMove { target: Target::Volume, before: 0.0, to: -6.0 })),
            (PartChange::Pan(0.5), Some(ControlMove { target: Target::Pan, before: 0.0, to: 0.5 })),
            (PartChange::Volume(0.0), None),
            (PartChange::Name("Bass".into()), None),
        ];
        for (change, want) in cases {
            let (mut doc, id) = one_part();
            let moved = doc.part_set(id, change.clone()).unwrap();
            assert_eq!(moved, want, "{change:?}");
        }
    }

    #[test]
    fn groups_nest_three_deep_and_a_move_that_makes_a_cycle_is_refused() {
        let mut doc = Document::default();
        let mut add = |name: &str| doc.part_add(PartOpts { name: Some(name.into()), ..PartOpts::default() }).unwrap();
        let (strings, violins, firsts, desk) = (add("Strings"), add("Violins"), add("Firsts"), add("Desk 1"));
        for (part, group) in [(violins, strings), (firsts, violins), (desk, firsts)] {
            doc.part_set(part, PartChange::Parent(Some(group))).expect("a group in a group");
        }
        assert_eq!(doc.project.part(desk).unwrap().parent, Some(firsts));
        let steps = doc.undo.history.len();
        let wrong = doc.part_set(strings, PartChange::Parent(Some(desk))).unwrap_err();
        assert_eq!(wrong.to_string(), "`Strings` cannot go into `Desk 1`: it holds that group");
        assert!(doc.part_set(strings, PartChange::Parent(Some(strings))).is_err(), "not into itself");
        assert_eq!(doc.undo.history.len(), steps, "a refused move makes no undo step");
        doc.part_remove(firsts).unwrap();
        assert_eq!(doc.project.part(desk).unwrap().parent, None, "the members of a removed group stand at the top");
    }

    #[test]
    fn a_part_keeps_its_kind_and_its_kind_clears() {
        let (mut doc, id) = one_part();
        let kind: KindId<PartFamily> = "vocal".parse().unwrap();
        doc.part_set(id, PartChange::Kind(Some(kind.clone()))).unwrap();
        assert_eq!(doc.project.part(id).unwrap().kind, Some(kind));
        doc.part_set(id, PartChange::Kind(None)).unwrap();
        assert_eq!(doc.project.part(id).unwrap().kind, None);
    }
}
