//! Linked racks: a rack definition of the project, and the splits of the
//! chains that are its instances (`Split::linked`).
//!
//! A definition holds a split and copies of its devices, with ids of its
//! own. An instance holds devices of its owner, with their own ids, plugin
//! states and lanes; [`RackOwn::ids`] says which id stands for which. When
//! the definition changes, each instance is made again from it: its devices
//! and order follow the definition, and its values follow too, except the
//! values that the instance overrides (`Keyed::follow`, `model/linked.rs`).
//!
//! The values that an instance can override are named by [`ValueKey`], with
//! the id of the definition: the mix, gain and values of a split, the gain,
//! pan, mute, solo and zone of a branch, the value of a macro, and the
//! bypass and the parameters of a device. Names, links and the order are
//! the definition's.

use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt;
use std::str::FromStr;
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::{Value, json};

use super::chain::{Split, Zone};
use super::ids::{DefId, DeviceId, NodeId, ParamKey};
use super::linked::{Keyed, Linkable, Linked};
use super::owner::OwnerRef;
use super::{DeviceInst, Project, Part};

/// A linked rack's definition.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RackDef {
    pub id: DefId<RackDef>,
    pub name: String,
    /// The rack, with the ids of the definition. Its `linked` is `None`.
    pub split: Split,
    /// The devices that `split` names, with the definition's ids.
    #[serde(default)]
    pub(crate) devices: Vec<Arc<DeviceInst>>,
}

impl Linkable for RackDef {
    type Overrides = RackOwn;

    fn id(&self) -> DefId<Self> {
        self.id
    }
}

/// What an instance of a rack has of its own.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RackOwn {
    /// For each id of the definition, the id that stands for it here.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub ids: BTreeMap<NodeId, NodeId>,
    /// The values that the instance keeps.
    #[serde(default, skip_serializing_if = "Keyed::is_empty")]
    pub values: Keyed<ValueKey>,
}

/// A value of a split, a branch or a macro that an instance can override.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Field {
    /// Of a split.
    Mix,
    /// Of a split or a branch.
    Gain,
    /// Of a split: the values of its kind, as one value.
    Values,
    /// Of a branch.
    Pan,
    Mute,
    Solo,
    Zone,
    /// Of a macro.
    Value,
}

impl Field {
    const ALL: [Field; 8] =
        [Self::Mix, Self::Gain, Self::Values, Self::Pan, Self::Mute, Self::Solo, Self::Zone, Self::Value];

    fn word(self) -> &'static str {
        match self {
            Self::Mix => "mix",
            Self::Gain => "gain",
            Self::Values => "values",
            Self::Pan => "pan",
            Self::Mute => "mute",
            Self::Solo => "solo",
            Self::Zone => "zone",
            Self::Value => "value",
        }
    }

    fn of(word: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|f| f.word() == word)
    }
}

/// The key of a value of a rack that an instance can override, with the
/// id of the definition.
///
/// Its text is the reference of the chain language: `#5.mix` for a field
/// of the split, branch or macro 5, `#7.ratio` for a parameter of device 7,
/// `#7.bypass` for its bypass. The id says what the node is, so a key of a
/// field names the node and not its kind. The file keeps the form of the
/// first version of linked racks (`5.mix`, `7.params.ratio`, `7.bypass`),
/// so its bytes do not change; [`ValueKey::from_str`] reads that form.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum ValueKey {
    Field { node: NodeId, field: Field },
    Bypass { device: DeviceId },
    Param { device: DeviceId, param: ParamKey },
}

impl ValueKey {
    /// The form that the file holds.
    fn file_form(&self) -> String {
        match self {
            Self::Field { node, field } => format!("{node}.{}", field.word()),
            Self::Bypass { device } => format!("{device}.bypass"),
            Self::Param { device, param } => format!("{device}.params.{param}"),
        }
    }
}

/// Why a key of a rack value is refused.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
#[error("`{0}` is not a key of a value of a rack: say #<id>.<field> or #<id>.<parameter>")]
pub struct BadKey(String);

impl FromStr for ValueKey {
    type Err = BadKey;

    /// The form that the file holds.
    fn from_str(text: &str) -> Result<Self, BadKey> {
        let bad = || BadKey(text.to_owned());
        let (id, rest) = text.split_once('.').ok_or_else(bad)?;
        let id: u64 = id.parse().map_err(|_| bad())?;
        if let Some(param) = rest.strip_prefix("params.") {
            if param.is_empty() {
                return Err(bad());
            }
            return Ok(Self::Param { device: id.into(), param: param.into() });
        }
        if rest == "bypass" {
            return Ok(Self::Bypass { device: id.into() });
        }
        Field::of(rest).map(|field| Self::Field { node: id.into(), field }).ok_or_else(bad)
    }
}

impl fmt::Display for ValueKey {
    /// The reference of the chain language: `#5.mix`, `#7.ratio`.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Field { node, field } => write!(f, "#{node}.{}", field.word()),
            Self::Bypass { device } => write!(f, "#{device}.bypass"),
            Self::Param { device, param } => write!(f, "#{device}.{param}"),
        }
    }
}

// In the order of the file form, so that a file lists the keys as before.
impl Ord for ValueKey {
    fn cmp(&self, other: &Self) -> Ordering {
        self.file_form().cmp(&other.file_form())
    }
}

impl PartialOrd for ValueKey {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Serialize for ValueKey {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.file_form())
    }
}

impl<'de> Deserialize<'de> for ValueKey {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        String::deserialize(deserializer)?.parse().map_err(serde::de::Error::custom)
    }
}

/// The link of an instance to its rack definition.
pub(crate) type RackLink = Linked<RackDef>;

/// The id of the definition that `here` stands for, by the instance's ids.
fn back_ids(link: &RackLink) -> HashMap<NodeId, NodeId> {
    link.overrides.ids.iter().map(|(def, here)| (*here, *def)).collect()
}

/// A value of a split, a branch or a macro that an instance can override.
enum Slot<'a> {
    Number(&'a mut f64),
    Flag(&'a mut bool),
    Zone(&'a mut Option<Zone>),
    Values(&'a mut serde_json::Map<String, Value>),
}

impl Slot<'_> {
    fn get(&self) -> Value {
        match self {
            Self::Number(n) => json!(**n),
            Self::Flag(b) => json!(**b),
            Self::Zone(z) => serde_json::to_value(**z).unwrap_or(Value::Null),
            Self::Values(v) => Value::Object((**v).clone()),
        }
    }

    /// Set the slot from a value that `get` gave; another value changes
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
/// id of its node and the field.
fn each_field(split: &mut Split, f: &mut impl FnMut(NodeId, Field, Slot)) {
    split.each_split_mut(&mut |s| {
        f(s.id, Field::Mix, Slot::Number(&mut s.mix));
        f(s.id, Field::Gain, Slot::Number(&mut s.gain));
        f(s.id, Field::Values, Slot::Values(&mut s.values));
        for m in &mut s.macros {
            f(m.id, Field::Value, Slot::Number(&mut m.value));
        }
        for b in &mut s.branches {
            f(b.id, Field::Gain, Slot::Number(&mut b.gain));
            f(b.id, Field::Pan, Slot::Number(&mut b.pan));
            f(b.id, Field::Mute, Slot::Flag(&mut b.mute));
            f(b.id, Field::Solo, Slot::Flag(&mut b.solo));
            f(b.id, Field::Zone, Slot::Zone(&mut b.zone));
        }
    });
}

/// The values of a rack (`split` and its devices) by key, with the ids
/// that `key_id` gives for its own: the definition's.
fn values_of(
    split: &Split,
    devices: &[Arc<DeviceInst>],
    key_id: &impl Fn(NodeId) -> Option<NodeId>,
) -> BTreeMap<ValueKey, Value> {
    let mut out = BTreeMap::new();
    let mut copy = split.clone();
    each_field(&mut copy, &mut |id, field, slot| {
        if let Some(node) = key_id(id) {
            out.insert(ValueKey::Field { node, field }, slot.get());
        }
    });
    let inside: HashSet<DeviceId> = split.devices().into_iter().collect();
    for d in devices.iter().filter(|d| inside.contains(&d.id.into())) {
        let Some(key) = key_id(d.id.into()) else { continue };
        let device = DeviceId::from(key);
        out.insert(ValueKey::Bypass { device }, json!(d.bypass));
        for (param, value) in &d.params {
            out.insert(ValueKey::Param { device, param: param.as_str().into() }, json!(value));
        }
    }
    out
}

/// Set the values of a rack whose ids are the keys' ids.
fn set_values(split: &mut Split, devices: &mut [DeviceInst], values: &BTreeMap<ValueKey, Value>) {
    each_field(split, &mut |node, field, mut slot| {
        if let Some(value) = values.get(&ValueKey::Field { node, field }) {
            slot.set(value);
        }
    });
    let by_id: HashMap<DeviceId, usize> = devices.iter().enumerate().map(|(i, d)| (d.id.into(), i)).collect();
    for (key, value) in values {
        match key {
            ValueKey::Bypass { device } => {
                if let (Some(&at), Some(bypass)) = (by_id.get(device), value.as_bool()) {
                    devices[at].bypass = bypass;
                }
            }
            ValueKey::Param { device, param } => {
                if let (Some(&at), Some(v)) = (by_id.get(device), value.as_f64()) {
                    devices[at].params.insert(param.to_string(), v);
                }
            }
            ValueKey::Field { .. } => {}
        }
    }
}

impl RackDef {
    fn values(&self) -> BTreeMap<ValueKey, Value> {
        values_of(&self.split, &self.devices, &|id| Some(id))
    }

    /// Whether `key` is a parameter of a device of the rack. A device keeps
    /// only the parameters that the project sets, so a parameter at its
    /// default is not among `values` and is still a value of the rack.
    fn has_param(&self, key: &ValueKey) -> bool {
        matches!(key, ValueKey::Param { device, .. } if self.devices.iter().any(|d| DeviceId::from(d.id) == *device))
    }

    /// The key that `text` names: the reference of the chain language
    /// (`#5.mix`, `#7.ratio`, with an id of the definition) or the form of
    /// the file (`7.params.ratio`).
    pub fn value_key(&self, text: &str) -> Result<ValueKey, BadKey> {
        let Some(reference) = text.strip_prefix('#') else { return text.parse() };
        let bad = || BadKey(text.to_owned());
        let (id, rest) = reference.split_once('.').ok_or_else(bad)?;
        let id: u64 = id.parse().map_err(|_| bad())?;
        if self.devices.iter().any(|d| d.id == id) {
            let device = DeviceId::from(id);
            return Ok(match rest {
                "bypass" => ValueKey::Bypass { device },
                "" => return Err(bad()),
                param => ValueKey::Param { device, param: param.into() },
            });
        }
        Field::of(rest).map(|field| ValueKey::Field { node: id.into(), field }).ok_or_else(bad)
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
        new_id: &mut dyn FnMut() -> NodeId,
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
        let used: HashSet<NodeId> = split.ids().into_iter().collect();
        instance.overrides.ids.retain(|def, _| used.contains(def));
        for def in &used {
            instance.overrides.ids.entry(*def).or_insert_with(&mut *new_id);
        }
        split.map_ids(&mut |id| instance.overrides.ids.get(&id).copied().unwrap_or(id));
        let had: HashMap<u64, &Arc<DeviceInst>> =
            here.map(|(_, d)| d.iter().map(|d| (d.id, d)).collect()).unwrap_or_default();
        for d in &mut devices {
            d.id = instance.overrides.ids[&NodeId::from(d.id)].get();
            if let Some(old) = had.get(&d.id) {
                *d = DeviceInst { bypass: d.bypass, params: std::mem::take(&mut d.params), ..(***old).clone() };
            }
        }
        split.linked = Some(instance);
        (split, devices)
    }
}

impl Project {
    pub fn rack(&self, id: DefId<RackDef>) -> Option<&Arc<RackDef>> {
        self.racks.get(id)
    }

    /// The split `split` of the chain of `owner`.
    fn owned_split(&self, owner: OwnerRef, split: NodeId) -> Result<(&Part, &Split)> {
        let t = self.owner(owner).with_context(|| format!("no {owner}"))?;
        let chain = t.chain.as_ref().with_context(|| format!("no split {split} in the chain of {owner}"))?;
        let s = chain.root.split(split).with_context(|| format!("{split} is not a split of the chain of {owner}"))?;
        Ok((t, s))
    }

    /// The split `split` of the chain of `owner`, to change.
    fn owned_split_mut(&mut self, owner: OwnerRef, split: NodeId) -> Result<&mut Split> {
        let t = self.owner_mut(owner).with_context(|| format!("no {owner}"))?;
        let chain = Arc::make_mut(t.chain.as_mut().context("no chain")?);
        chain.root.split_mut(split).context("no split")
    }

    /// Make the split `split` of the chain of `owner` the first instance of
    /// a new rack definition named `name`. Returns the definition's id.
    pub fn rack_define(
        &mut self,
        owner: OwnerRef,
        split: NodeId,
        name: &str,
        new_id: &mut dyn FnMut() -> NodeId,
    ) -> Result<DefId<RackDef>> {
        let (t, s) = self.owned_split(owner, split)?;
        let chain = t.chain.as_ref().context("no chain")?;
        if chain.root.id == split {
            bail!("the root of a chain cannot be a linked rack: wrap its devices in a rack first");
        }
        let mut nested = false;
        s.each_split(&mut |inner| nested |= inner.linked.is_some());
        if nested || chain.root.path_to(split).iter().any(|p| p.linked.is_some()) {
            bail!("a linked rack cannot hold another linked rack, or be inside one");
        }
        let id = DefId::new(new_id().get());
        let mut instance = RackLink::new(id);
        let mut def_split = s.clone();
        def_split.map_ids(&mut |here| {
            let def = new_id();
            instance.overrides.ids.insert(def, here);
            def
        });
        let back = back_ids(&instance);
        let inside: HashSet<DeviceId> = s.devices().into_iter().collect();
        let devices = t
            .devices
            .iter()
            .filter(|d| inside.contains(&d.id.into()))
            .map(|d| Arc::new(DeviceInst { id: back[&NodeId::from(d.id)].get(), ..(**d).clone() }))
            .collect();
        let name = if name.is_empty() { s.name.clone() } else { name.to_owned() };
        self.racks.push(RackDef { id, name: name.clone(), split: def_split, devices });
        let s = self.owned_split_mut(owner, split)?;
        s.linked = Some(instance);
        if s.name.is_empty() {
            s.name = name;
        }
        Ok(id)
    }

    /// A new instance of the definition `rack`: the rack and its devices,
    /// to place in a chain.
    pub(crate) fn rack_instance(
        &self,
        rack: DefId<RackDef>,
        new_id: &mut dyn FnMut() -> NodeId,
    ) -> Result<(Split, Vec<DeviceInst>)> {
        let def = self.rack(rack).with_context(|| format!("no rack definition {rack}"))?;
        Ok(def.instance(RackLink::new(rack), None, None, new_id))
    }

    /// The instance split `split` of the chain of `owner`, and the
    /// definition it follows.
    fn linked(&self, owner: OwnerRef, split: NodeId) -> Result<(RackLink, Arc<RackDef>)> {
        let (_, s) = self.owned_split(owner, split)?;
        let instance = s.linked.clone().with_context(|| format!("{} is not a linked rack", label(s)))?;
        let def = self.rack(instance.of).with_context(|| format!("no rack definition {}", instance.of))?.clone();
        Ok((instance, def))
    }

    /// Make the instance `split` again from its definition, as `old` was
    /// before the change (`None`: take each value of the definition that
    /// the instance does not override).
    fn rack_follow(
        &mut self,
        owner: OwnerRef,
        split: NodeId,
        old: Option<&RackDef>,
        new_id: &mut dyn FnMut() -> NodeId,
    ) -> Result<()> {
        let (t, here) = self.owned_split(owner, split)?;
        let instance = here.linked.clone().context("not linked")?;
        let def = self.rack(instance.of).context("no rack definition")?.clone();
        let (made, devices) = def.instance(instance, Some((here, &t.devices)), old, new_id);
        let gone: HashSet<u64> = here.devices().into_iter().map(DeviceId::get).collect();
        *self.owned_split_mut(owner, split)? = made;
        put_devices(self.owner_mut(owner).context("no owner")?, &gone, devices);
        Ok(())
    }

    /// Make each instance of `rack` (but `skip`) again from its definition,
    /// which was `old` before it changed.
    fn rack_spread(
        &mut self,
        rack: DefId<RackDef>,
        old: &RackDef,
        skip: Option<NodeId>,
        new_id: &mut dyn FnMut() -> NodeId,
    ) -> Result<()> {
        let mut instances = Vec::new();
        for (owner, chain) in self.chains() {
            for (split, of) in chain.root.linked_racks() {
                if of == rack && Some(split) != skip {
                    instances.push((owner, split));
                }
            }
        }
        for (owner, split) in instances {
            self.rack_follow(owner, split, Some(old), new_id)?;
        }
        Ok(())
    }

    /// Make the definition of the instance `split` what the instance is
    /// now, and each other instance follow it. With `keep_values`, only
    /// the parts and their order change: a value that the definition had
    /// stays, and the instance overrides it where it differs. Without, the
    /// instance's values become the definition's.
    pub fn rack_apply(
        &mut self,
        owner: OwnerRef,
        split: NodeId,
        keep_values: bool,
        new_id: &mut dyn FnMut() -> NodeId,
    ) -> Result<()> {
        let (mut instance, old) = self.linked(owner, split)?;
        let (t, here) = self.owned_split(owner, split)?;
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
        let inside: HashSet<DeviceId> = here.devices().into_iter().collect();
        let mut devices: Vec<DeviceInst> = t
            .devices
            .iter()
            .filter(|d| inside.contains(&d.id.into()))
            .map(|d| DeviceInst { id: back[&NodeId::from(d.id)].get(), ..(**d).clone() })
            .collect();
        if keep_values {
            set_values(&mut def_split, &mut devices, &old.values());
        }
        let def = RackDef { split: def_split, devices: devices.into_iter().map(Arc::new).collect(), ..(*old).clone() };
        let id = def.id;
        if !self.racks.replace(def) {
            bail!("no rack definition {id}");
        }
        // The instance's ids now name the parts it added to the definition.
        self.owned_split_mut(owner, split)?.linked = Some(instance);
        self.rack_spread(id, &old, Some(split), new_id)?;
        self.rack_follow(owner, split, Some(&old), new_id)?;
        if !keep_values {
            // Its values are the definition's now.
            set_overrides(self, owner, split, Keyed::default())?;
        }
        Ok(())
    }

    /// Give the instance `split` each value of its definition: its
    /// overrides go. Gives how many went.
    pub fn rack_reset(&mut self, owner: OwnerRef, split: NodeId, new_id: &mut dyn FnMut() -> NodeId) -> Result<usize> {
        let (instance, _) = self.linked(owner, split)?;
        let count = instance.overrides.values.0.len();
        set_overrides(self, owner, split, Keyed::default())?;
        self.rack_follow(owner, split, None, new_id)?;
        Ok(count)
    }

    /// The instance `split` keeps what it is, and follows no definition.
    pub fn rack_unlink(&mut self, owner: OwnerRef, split: NodeId) -> Result<()> {
        self.linked(owner, split)?;
        self.owned_split_mut(owner, split)?.linked = None;
        Ok(())
    }

    /// Change a value of the definition `rack`, by its key (see
    /// [`RackDef::value_key`]), and spread the change to each instance.
    pub fn rack_set(
        &mut self,
        rack: DefId<RackDef>,
        key: &str,
        value: Value,
        new_id: &mut dyn FnMut() -> NodeId,
    ) -> Result<()> {
        let old = self.rack(rack).with_context(|| format!("no rack definition {rack}"))?.clone();
        let key = old.value_key(key)?;
        if !old.values().contains_key(&key) && !old.has_param(&key) {
            bail!("the rack {} has no value `{key}`", old.name);
        }
        let mut def = (*old).clone();
        let mut devices = def.device_copies();
        set_values(&mut def.split, &mut devices, &BTreeMap::from([(key, value)]));
        def.devices = devices.into_iter().map(Arc::new).collect();
        self.racks.replace(def);
        self.rack_spread(rack, &old, None, new_id)
    }

    /// The keys of the values that the instance `split` overrides, with the
    /// ids of the definition.
    pub fn rack_overrides(&self, owner: OwnerRef, split: NodeId) -> Result<Vec<ValueKey>> {
        let (instance, _) = self.linked(owner, split)?;
        Ok(instance.overrides.values.0.into_iter().collect())
    }
}

fn set_overrides(p: &mut Project, owner: OwnerRef, split: NodeId, values: Keyed<ValueKey>) -> Result<()> {
    if let Some(linked) = &mut p.owned_split_mut(owner, split)?.linked {
        linked.overrides.values = values;
    }
    Ok(())
}

/// Put the devices of a rack made again on its owner: the devices of
/// `gone` that it does not have go (with their lanes), the others change
/// in place, and new ones join the list. The chain's order comes after.
fn put_devices(t: &mut Part, gone: &HashSet<u64>, devices: Vec<DeviceInst>) {
    let mut made: HashMap<u64, DeviceInst> = devices.into_iter().map(|d| (d.id, d)).collect();
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
pub(super) fn label(split: &Split) -> String {
    if split.name.is_empty() { format!("{} split {}", split.kind, split.id) } else { format!("\"{}\"", split.name) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_value_key_reads_the_file_form_and_writes_a_reference() {
        for (file, reference) in
            [("5.mix", "#5.mix"), ("5.gain", "#5.gain"), ("7.bypass", "#7.bypass"), ("7.params.ratio", "#7.ratio")]
        {
            let key: ValueKey = file.parse().unwrap();
            assert_eq!(key.to_string(), reference);
            assert_eq!(serde_json::to_value(&key).unwrap(), json!(file), "the file keeps {file}");
        }
        for bad in ["5", "x.mix", "5.drive", "5.params."] {
            assert!(bad.parse::<ValueKey>().is_err(), "{bad} is refused");
        }
    }
}
