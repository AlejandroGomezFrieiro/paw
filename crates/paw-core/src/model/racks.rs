//! Linked racks: a rack definition of the project, and the splits of the
//! tracks' graphs that are its instances (`Split::linked`).
//!
//! A definition holds a split and copies of its devices, with ids of its
//! own. An instance holds devices of its track, with their own ids, plugin
//! states and lanes; [`RackOwn::ids`] says which id stands for which. When
//! the definition changes, each instance is made again from it: its devices
//! and order follow the definition, and its values follow too, except the
//! values that the instance overrides (`Keyed::follow`, `model/linked.rs`).
//!
//! The values that an instance can override, by key (with the id of the
//! definition): `<split>.mix`, `<split>.gain`, `<split>.values` (the values
//! of its kind), `<branch>.gain`, `.pan`, `.mute`, `.solo`, `.zone`,
//! `<macro>.value`, `<device>.bypass` and `<device>.params.<key>`. Names,
//! links and the order are the definition's.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::graph::{Split, Zone};
use super::linked::{Keyed, Linked};
use super::{DeviceInst, Id, Project, Track};

/// A linked rack's definition.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RackDef {
    pub id: Id,
    pub name: String,
    /// The rack, with the ids of the definition. Its `linked` is `None`.
    pub split: Split,
    /// The devices that `split` names, with the definition's ids.
    #[serde(default)]
    pub devices: Vec<Arc<DeviceInst>>,
}

/// A split that is an instance of a rack definition: the definition's id,
/// and what the instance has of its own.
pub type RackLink = Linked<Id, RackOwn>;

/// What an instance of a rack has of its own.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RackOwn {
    /// For each id of the definition, the id that stands for it here.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub ids: BTreeMap<Id, Id>,
    /// The keys of the values that the instance keeps.
    #[serde(default, skip_serializing_if = "Keyed::is_empty")]
    pub values: Keyed,
}

fn new_link(of: Id) -> RackLink {
    Linked { of, overrides: RackOwn::default() }
}

/// The id of the definition that `here` stands for, by the instance's ids.
fn back_ids(link: &RackLink) -> HashMap<Id, Id> {
    link.overrides.ids.iter().map(|(def, here)| (*here, *def)).collect()
}

/// A value of a split, a branch or a macro that an instance can override.
enum Field<'a> {
    Number(&'a mut f64),
    Flag(&'a mut bool),
    Zone(&'a mut Option<Zone>),
    Values(&'a mut serde_json::Map<String, Value>),
}

impl Field<'_> {
    fn get(&self) -> Value {
        match self {
            Self::Number(n) => json!(**n),
            Self::Flag(b) => json!(**b),
            Self::Zone(z) => serde_json::to_value(**z).unwrap_or(Value::Null),
            Self::Values(v) => Value::Object((**v).clone()),
        }
    }

    /// Set the field from a value that `get` gave; another value changes
    /// nothing.
    fn set(&mut self, value: &Value) {
        match self {
            Self::Number(n) => {
                if let Some(v) = value.as_f64() {
                    **n = v;
                }
            }
            Self::Flag(b) => {
                if let Some(v) = value.as_bool() {
                    **b = v;
                }
            }
            Self::Zone(z) => {
                if let Ok(v) = serde_json::from_value(value.clone()) {
                    **z = v;
                }
            }
            Self::Values(v) => {
                if let Value::Object(map) = value {
                    **v = map.clone();
                }
            }
        }
    }
}

/// Call `f` with each value of the tree that an instance can override: the
/// id of its node and the name of the field.
fn each_field(split: &mut Split, f: &mut impl FnMut(Id, &'static str, Field)) {
    split.each_split_mut(&mut |s| {
        f(s.id, "mix", Field::Number(&mut s.mix));
        f(s.id, "gain", Field::Number(&mut s.gain));
        f(s.id, "values", Field::Values(&mut s.values));
        for m in &mut s.macros {
            f(m.id, "value", Field::Number(&mut m.value));
        }
        for b in &mut s.branches {
            f(b.id, "gain", Field::Number(&mut b.gain));
            f(b.id, "pan", Field::Number(&mut b.pan));
            f(b.id, "mute", Field::Flag(&mut b.mute));
            f(b.id, "solo", Field::Flag(&mut b.solo));
            f(b.id, "zone", Field::Zone(&mut b.zone));
        }
    });
}

/// The values of a rack (`split` and its devices) by key, with the ids
/// that `key_id` gives for its own: the definition's.
fn values_of(
    split: &Split,
    devices: &[Arc<DeviceInst>],
    key_id: &impl Fn(Id) -> Option<Id>,
) -> BTreeMap<String, Value> {
    let mut out = BTreeMap::new();
    let mut copy = split.clone();
    each_field(&mut copy, &mut |id, name, field| {
        if let Some(key) = key_id(id) {
            out.insert(format!("{key}.{name}"), field.get());
        }
    });
    let inside: HashSet<Id> = split.devices().into_iter().collect();
    for d in devices.iter().filter(|d| inside.contains(&d.id)) {
        let Some(key) = key_id(d.id) else { continue };
        out.insert(format!("{key}.bypass"), json!(d.bypass));
        for (param, value) in &d.params {
            out.insert(format!("{key}.params.{param}"), json!(value));
        }
    }
    out
}

/// Set the values of a rack whose ids are the keys' ids.
fn set_values(split: &mut Split, devices: &mut [DeviceInst], values: &BTreeMap<String, Value>) {
    each_field(split, &mut |id, name, mut field| {
        if let Some(value) = values.get(&format!("{id}.{name}")) {
            field.set(value);
        }
    });
    for d in devices {
        if let Some(bypass) = values.get(&format!("{}.bypass", d.id)).and_then(Value::as_bool) {
            d.bypass = bypass;
        }
        let prefix = format!("{}.params.", d.id);
        for (key, value) in values.range(prefix.clone()..) {
            let Some(param) = key.strip_prefix(&prefix) else {
                break;
            };
            if let Some(v) = value.as_f64() {
                d.params.insert(param.to_owned(), v);
            }
        }
    }
}

impl RackDef {
    fn values(&self) -> BTreeMap<String, Value> {
        values_of(&self.split, &self.devices, &|id| Some(id))
    }

    /// The definition's devices, as copies to change.
    fn device_copies(&self) -> Vec<DeviceInst> {
        self.devices.iter().map(|d| (**d).clone()).collect()
    }

    /// A rack made from the definition for an instance: `here` is what the
    /// instance is now (none for a new one), `old` the definition before
    /// the change. The instance's ids stand for the definition's (new ids
    /// from `new_id` for parts it did not have). Gives the rack and its
    /// devices; a device that the instance had keeps its state and fields,
    /// with the bypass and parameters of the rack.
    fn instance(
        &self,
        mut instance: RackLink,
        here: Option<(&Split, &[Arc<DeviceInst>])>,
        old: Option<&RackDef>,
        new_id: &mut dyn FnMut() -> Id,
    ) -> (Split, Vec<DeviceInst>) {
        let mut split = self.split.clone();
        let mut devices = self.device_copies();
        // The values, by the definition's ids.
        let here_values = here.map(|(s, d)| {
            let back = back_ids(&instance);
            values_of(s, d, &|id| back.get(&id).copied())
        });
        let values = instance.overrides.values.follow(
            old.map(RackDef::values).as_ref(),
            &self.values(),
            &here_values.unwrap_or_default(),
        );
        set_values(&mut split, &mut devices, &values);
        // The ids: the instance's for the parts it had, new ones for the rest.
        let used: HashSet<Id> = split.ids().into_iter().collect();
        instance.overrides.ids.retain(|def, _| used.contains(def));
        for def in &used {
            instance.overrides.ids.entry(*def).or_insert_with(&mut *new_id);
        }
        split.map_ids(&mut |id| instance.overrides.ids.get(&id).copied().unwrap_or(id));
        let had: HashMap<Id, &Arc<DeviceInst>> =
            here.map(|(_, d)| d.iter().map(|d| (d.id, d)).collect()).unwrap_or_default();
        for d in &mut devices {
            d.id = instance.overrides.ids[&d.id];
            if let Some(old) = had.get(&d.id) {
                *d = DeviceInst { bypass: d.bypass, params: std::mem::take(&mut d.params), ..(***old).clone() };
            }
        }
        split.linked = Some(instance);
        (split, devices)
    }
}

impl Project {
    pub fn rack(&self, id: Id) -> Option<&Arc<RackDef>> {
        self.racks.iter().find(|r| r.id == id)
    }

    /// The track whose graph holds the split, the node, the branch or the
    /// macro `id`.
    pub fn graph_track(&self, id: Id) -> Option<Id> {
        self.all_tracks().find(|t| t.graph.as_ref().is_some_and(|g| !g.root.path_to(id).is_empty())).map(|t| t.id)
    }

    /// Make the split `split` the first instance of a new rack definition
    /// named `name`. Returns the definition's id.
    pub fn rack_define(&mut self, split: Id, name: &str, new_id: &mut dyn FnMut() -> Id) -> Result<Id> {
        let track = self.graph_track(split).with_context(|| format!("no split {split}"))?;
        let t = self.track(track).context("no track")?;
        let graph = t.graph.as_ref().context("no graph")?;
        if graph.root.id == split {
            bail!("the root of a graph cannot be a linked rack: wrap its devices in a rack first");
        }
        let s = graph.root.split(split).with_context(|| format!("{split} is not a split"))?;
        let mut nested = false;
        s.each_split(&mut |inner| nested |= inner.linked.is_some());
        if nested || graph.root.path_to(split).iter().any(|p| p.linked.is_some()) {
            bail!("a linked rack cannot hold another linked rack, or be inside one");
        }
        let id = new_id();
        let mut instance = new_link(id);
        let mut def_split = s.clone();
        def_split.map_ids(&mut |here| {
            let def = new_id();
            instance.overrides.ids.insert(def, here);
            def
        });
        let back = back_ids(&instance);
        let inside: HashSet<Id> = s.devices().into_iter().collect();
        let devices = t
            .devices
            .iter()
            .filter(|d| inside.contains(&d.id))
            .map(|d| Arc::new(DeviceInst { id: back[&d.id], ..(**d).clone() }))
            .collect();
        let name = if name.is_empty() { s.name.clone() } else { name.to_owned() };
        self.racks.push(Arc::new(RackDef { id, name: name.clone(), split: def_split, devices }));
        let t = self.track_mut(track).context("no track")?;
        let s = Arc::make_mut(t.graph.as_mut().context("no graph")?).root.split_mut(split).context("no split")?;
        s.linked = Some(instance);
        if s.name.is_empty() {
            s.name = name;
        }
        Ok(id)
    }

    /// A new instance of the definition `rack`: the rack and its devices,
    /// to place in a graph.
    pub fn rack_instance(&self, rack: Id, new_id: &mut dyn FnMut() -> Id) -> Result<(Split, Vec<DeviceInst>)> {
        let def = self.rack(rack).with_context(|| format!("no rack definition {rack}"))?;
        Ok(def.instance(new_link(rack), None, None, new_id))
    }

    /// The instance split `split` and the definition it follows.
    fn linked(&self, split: Id) -> Result<(Id, RackLink, Arc<RackDef>)> {
        let track = self.graph_track(split).with_context(|| format!("no split {split}"))?;
        let s = self
            .track(track)
            .and_then(|t| t.graph.as_ref())
            .and_then(|g| g.root.split(split))
            .with_context(|| format!("{split} is not a split"))?;
        let instance = s.linked.clone().with_context(|| format!("{} is not a linked rack", label(s)))?;
        let def = self.rack(instance.of).with_context(|| format!("no rack definition {}", instance.of))?.clone();
        Ok((track, instance, def))
    }

    /// Make the instance `split` again from its definition, as `old` was
    /// before the change (`None`: take each value of the definition that
    /// the instance does not override).
    fn rack_follow(
        &mut self,
        track: Id,
        split: Id,
        old: Option<&RackDef>,
        new_id: &mut dyn FnMut() -> Id,
    ) -> Result<()> {
        let t = self.track(track).context("no track")?;
        let here = t.graph.as_ref().and_then(|g| g.root.split(split)).context("no split")?;
        let instance = here.linked.clone().context("not linked")?;
        let def = self.rack(instance.of).context("no rack definition")?.clone();
        let (made, devices) = def.instance(instance, Some((here, &t.devices)), old, new_id);
        let gone: HashSet<Id> = here.devices().into_iter().collect();
        let t = self.track_mut(track).context("no track")?;
        let graph = Arc::make_mut(t.graph.as_mut().context("no graph")?);
        *graph.root.split_mut(split).context("no split")? = made;
        put_devices(t, &gone, devices);
        Ok(())
    }

    /// Make each instance of `rack` (but `skip`) again from its definition,
    /// which was `old` before it changed.
    fn rack_spread(&mut self, rack: Id, old: &RackDef, skip: Option<Id>, new_id: &mut dyn FnMut() -> Id) -> Result<()> {
        let mut instances = Vec::new();
        for t in self.all_tracks() {
            if let Some(g) = &t.graph {
                g.root.each_split(&mut |s| {
                    if s.linked.as_ref().is_some_and(|l| l.of == rack) && Some(s.id) != skip {
                        instances.push((t.id, s.id));
                    }
                });
            }
        }
        for (track, split) in instances {
            self.rack_follow(track, split, Some(old), new_id)?;
        }
        Ok(())
    }

    /// Make the definition of the instance `split` what the instance is
    /// now, and each other instance follow it. With `keep_values`, only
    /// the parts and their order change: a value that the definition had
    /// stays, and the instance overrides it where it differs. Without, the
    /// instance's values become the definition's.
    pub fn rack_apply(&mut self, split: Id, keep_values: bool, new_id: &mut dyn FnMut() -> Id) -> Result<()> {
        let (track, mut instance, old) = self.linked(split)?;
        let t = self.track(track).context("no track")?;
        let here = t.graph.as_ref().and_then(|g| g.root.split(split)).context("no split")?;
        let mut back = back_ids(&instance);
        let mut def_split = here.clone();
        def_split.linked = None;
        def_split.map_ids(&mut |id| {
            *back.entry(id).or_insert_with(|| {
                let def = new_id();
                instance.overrides.ids.insert(def, id);
                def
            })
        });
        let inside: HashSet<Id> = here.devices().into_iter().collect();
        let mut devices: Vec<DeviceInst> = t
            .devices
            .iter()
            .filter(|d| inside.contains(&d.id))
            .map(|d| DeviceInst { id: back[&d.id], ..(**d).clone() })
            .collect();
        if keep_values {
            set_values(&mut def_split, &mut devices, &old.values());
        }
        let def = RackDef { split: def_split, devices: devices.into_iter().map(Arc::new).collect(), ..(*old).clone() };
        let id = def.id;
        *self.racks.iter_mut().find(|r| r.id == id).context("no rack definition")? = Arc::new(def);
        // The instance's ids now name the parts it added to the definition.
        set_linked(self, track, split, instance)?;
        self.rack_spread(id, &old, Some(split), new_id)?;
        self.rack_follow(track, split, Some(&old), new_id)?;
        if !keep_values {
            // Its values are the definition's now.
            set_linked_overrides(self, track, split, Default::default())?;
        }
        Ok(())
    }

    /// Give the instance `split` each value of its definition: its
    /// overrides go.
    pub fn rack_reset(&mut self, split: Id, new_id: &mut dyn FnMut() -> Id) -> Result<usize> {
        let (track, instance, _) = self.linked(split)?;
        let count = instance.overrides.values.0.len();
        set_linked_overrides(self, track, split, Default::default())?;
        self.rack_follow(track, split, None, new_id)?;
        Ok(count)
    }

    /// The instance `split` keeps what it is, and follows no definition.
    pub fn rack_unlink(&mut self, split: Id) -> Result<()> {
        let (track, _, _) = self.linked(split)?;
        let t = self.track_mut(track).context("no track")?;
        let graph = Arc::make_mut(t.graph.as_mut().context("no graph")?);
        graph.root.split_mut(split).context("no split")?.linked = None;
        Ok(())
    }

    /// Change a value of the definition `rack`, by its key (see the head of
    /// this file), and spread the change to each instance.
    pub fn rack_set(&mut self, rack: Id, key: &str, value: Value, new_id: &mut dyn FnMut() -> Id) -> Result<()> {
        let old = self.rack(rack).with_context(|| format!("no rack definition {rack}"))?.clone();
        if !old.values().contains_key(key) {
            bail!("the rack {} has no value `{key}`", old.name);
        }
        let mut def = (*old).clone();
        let mut devices = def.device_copies();
        set_values(&mut def.split, &mut devices, &BTreeMap::from([(key.to_owned(), value)]));
        def.devices = devices.into_iter().map(Arc::new).collect();
        *self.racks.iter_mut().find(|r| r.id == rack).context("no rack definition")? = Arc::new(def);
        self.rack_spread(rack, &old, None, new_id)
    }

    /// The overrides of the instance `split`, by key.
    pub fn rack_overrides(&self, split: Id) -> Result<Vec<String>> {
        Ok(self.linked(split)?.1.overrides.values.0.into_iter().collect())
    }
}

fn set_linked(p: &mut Project, track: Id, split: Id, instance: RackLink) -> Result<()> {
    let t = p.track_mut(track).context("no track")?;
    let graph = Arc::make_mut(t.graph.as_mut().context("no graph")?);
    graph.root.split_mut(split).context("no split")?.linked = Some(instance);
    Ok(())
}

fn set_linked_overrides(p: &mut Project, track: Id, split: Id, overrides: Keyed) -> Result<()> {
    let t = p.track_mut(track).context("no track")?;
    let graph = Arc::make_mut(t.graph.as_mut().context("no graph")?);
    let s = graph.root.split_mut(split).context("no split")?;
    if let Some(linked) = &mut s.linked {
        linked.overrides.values = overrides;
    }
    Ok(())
}

/// Put the devices of a rack made again on its track: the devices of
/// `gone` that it does not have go (with their lanes), the others change
/// in place, and new ones join the list. The graph's order comes after.
fn put_devices(t: &mut Track, gone: &HashSet<Id>, devices: Vec<DeviceInst>) {
    let mut made: HashMap<Id, DeviceInst> = devices.into_iter().map(|d| (d.id, d)).collect();
    t.devices.retain(|d| !gone.contains(&d.id) || made.contains_key(&d.id));
    t.lanes.retain(|l| l.target.device().is_none_or(|d| !gone.contains(&d) || made.contains_key(&d)));
    for d in &mut t.devices {
        // Only the bypass and the parameters come from the rack.
        if let Some(new) = made.remove(&d.id)
            && (d.bypass != new.bypass || d.params != new.params)
        {
            *d = Arc::new(new);
        }
    }
    let mut rest: Vec<DeviceInst> = made.into_values().collect();
    rest.sort_by_key(|d| d.id);
    t.devices.extend(rest.into_iter().map(Arc::new));
}

/// A split as a message names it: its name, else its kind and id.
pub fn label(split: &Split) -> String {
    if split.name.is_empty() { format!("{} split {}", split.kind, split.id) } else { format!("\"{}\"", split.name) }
}
