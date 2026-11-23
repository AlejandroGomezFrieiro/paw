//! Nests (subprojects): make one, read one, change one. Each change is one
//! undo step. The model and its rules are in `model/nest.rs`; the files in
//! `folder/nests.rs`.

use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde_json::{Map, Value, json};

use super::Document;
use crate::model::{
    Clip, ClipContent, DeviceInst, Id, Lane, Nest, NestId, NestMeter, NestPlay, NestTempo, Target, Track,
};
use crate::session::{de, de_meta, holds};

/// The length of a nest made with none: 8 bars of 4/4.
const DEFAULT_LENGTH: f64 = 32.0;

/// What `paw.api.nest_add` takes.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct NestOpts {
    pub name: Option<String>,
    /// Beats; 32 when absent.
    pub length: Option<f64>,
    pub tempo: Option<NestTempo>,
    pub meter: Option<NestMeter>,
    pub kind: Option<String>,
    pub meta: Option<Value>,
}

/// A field of a nest that [`Document::nest_set`] changes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum NestField {
    Name,
    Length,
    Tempo,
    Meter,
    Kind,
    Meta,
}

impl std::str::FromStr for NestField {
    type Err = anyhow::Error;

    fn from_str(key: &str) -> Result<Self> {
        Ok(match key {
            "name" => Self::Name,
            "length" => Self::Length,
            "tempo" => Self::Tempo,
            "meter" => Self::Meter,
            "kind" => Self::Kind,
            "meta" => Self::Meta,
            _ => bail!("subprojects have no settable field `{key}`"),
        })
    }
}

impl NestField {
    fn set(self, nest: &mut Nest, key: &str, value: Value) -> Result<()> {
        match self {
            Self::Name => nest.name = de::<String>(key, value)?.trim().to_string(),
            Self::Length => nest.length = de(key, value)?,
            Self::Tempo => nest.tempo = de(key, value)?,
            Self::Meter => nest.meter = de(key, value)?,
            Self::Kind => nest.kind = de(key, value)?,
            Self::Meta => nest.meta = de_meta(key, value)?,
        }
        Ok(())
    }
}

impl Document {
    /// Make a nest with its master track and no other track. Returns its id.
    pub(crate) fn nest_add(&mut self, opts: NestOpts) -> Result<NestId> {
        let id = NestId(self.new_id());
        let master = self.new_id();
        let name = match opts.name.as_deref().map(str::trim) {
            Some(name) if !name.is_empty() => name.to_string(),
            _ => format!("Nest {}", self.project.nests.len() + 1),
        };
        let nest = Nest {
            id,
            name,
            length: opts.length.unwrap_or(DEFAULT_LENGTH),
            tempo: opts.tempo.unwrap_or_default(),
            meter: opts.meter.unwrap_or_default(),
            master,
            kind: opts.kind,
            meta: opts.meta.map_or_else(|| Ok(Map::new()), |m| de_meta("meta", m))?,
            source: None,
            origin: None,
        };
        let mut track = Track::new(master);
        track.name = "Master".into();
        track.nest = Some(id);
        let mut candidate = self.project.clone();
        candidate.tracks.push(Arc::new(track));
        candidate.nests.insert(id, Arc::new(nest));
        crate::model::check_nest(&candidate, id, &candidate.nests[&id])?;
        self.edit(|p| {
            *p = candidate;
            Ok(id)
        })
    }

    /// A nest as a table: its fields, `tracks` (its tracks in order, without
    /// the master) and `used` (whether the song plays it).
    pub(crate) fn nest_view(&self, id: NestId) -> Result<Value> {
        let nest = self
            .project
            .nest(id)
            .with_context(|| format!("no subproject {id}"))?;
        let tracks: Vec<Id> = self
            .project
            .nest_tracks(id)
            .map(|t| t.id)
            .filter(|t| *t != nest.master)
            .collect();
        let mut view = serde_json::to_value(&**nest)?;
        let map = view.as_object_mut().context("a subproject")?;
        map.insert("tracks".into(), json!(tracks));
        map.insert("used".into(), json!(self.project.nests_in_use().contains(&id)));
        map.entry("meta").or_insert_with(|| json!({}));
        Ok(view)
    }

    /// One field of a nest's own (not `tracks` or `used`): quicker than
    /// [`Document::nest_view`], which looks at every clip.
    pub(crate) fn nest_field(&self, id: NestId, key: &str) -> Result<Value> {
        let nest = self
            .project
            .nest(id)
            .with_context(|| format!("no subproject {id}"))?;
        Ok(match key {
            "name" => json!(nest.name),
            "length" => json!(nest.length),
            "master" => json!(nest.master),
            _ => serde_json::to_value(&**nest)?
                .get(key)
                .cloned()
                .unwrap_or(Value::Null),
        })
    }

    /// The ids of the nests, in the order they were made.
    pub(crate) fn nest_list(&self) -> Vec<NestId> {
        self.project.nests.keys().copied().collect()
    }

    /// Change one field of a nest. A value that is as it was is no change.
    /// A new tempo keeps the song's blocks of the nest on the beats of the
    /// nest they play: their length in the song follows it.
    pub(crate) fn nest_set(&mut self, id: NestId, key: &str, value: Value) -> Result<()> {
        if holds(&self.nest_view(id), key, &value) {
            return Ok(());
        }
        let field: NestField = key.parse()?;
        let was = self
            .project
            .nest(id)
            .with_context(|| format!("no subproject {id}"))?
            .clone();
        let mut nest = (*was).clone();
        field.set(&mut nest, key, value)?;
        crate::model::check_nest(&self.project, id, &nest)?;
        self.edit(|p| {
            p.nests.insert(id, Arc::new(nest));
            if field == NestField::Tempo {
                p.fit_blocks(id, &was);
            }
            Ok(())
        })
    }
}

/// Two blocks are one instance of a nest when they place it at the same
/// start, for the same length, from the same beat of it (the stems of one
/// block are one instance).
fn same_instance(a: &Clip, b: &Clip) -> bool {
    let offset = |c: &Clip| match &c.content {
        ClipContent::Nest { offset, .. } => *offset,
        _ => 0.0,
    };
    (a.start - b.start).abs() < 1e-9 && (a.length - b.length).abs() < 1e-9 && (offset(a) - offset(b)).abs() < 1e-9
}

impl Document {
    /// Make the instance of block `clip` a nest of its own (FL Studio's
    /// "make unique"): a copy of its nest, its tracks, devices, lanes and
    /// clips with new ids, named `Ballad 2`. The block, and the stems of
    /// the same instance, then place the copy. One undo step. Returns the
    /// copy's id.
    pub(crate) fn nest_unique(&mut self, clip: Id) -> Result<NestId> {
        let p = &self.project;
        let block = p.clip(clip).with_context(|| format!("no clip {clip}"))?.clone();
        let ClipContent::Nest { nest: old, .. } = &block.content else {
            bail!("not a block of a subproject: put the cursor on one");
        };
        let old = *old;
        let held = p.nest(old).context("its subproject is gone")?.clone();
        // The clips of this instance, and whether another instance plays it.
        let mut ours = Vec::new();
        let mut others = 0;
        for t in p.all_tracks() {
            for c in t.clips.iter().chain(&t.cues) {
                if matches!(&c.content, ClipContent::Nest { nest, .. } if *nest == old) {
                    if same_instance(c, &block) {
                        ours.push(c.id);
                    } else {
                        others += 1;
                    }
                }
            }
        }
        if others == 0 {
            bail!("{} has one block: it is a subproject of its own already", held.name);
        }
        let names: BTreeSet<&str> = p.nests.values().map(|n| n.name.as_str()).collect();
        let name = (2..)
            .map(|n| format!("{} {n}", held.name))
            .find(|n| !names.contains(n.as_str()))
            .expect("a free name");
        // New ids for the tracks first: their routes point at each other.
        let id = NestId(self.new_id());
        let sources: Vec<Arc<Track>> = self.project.nest_tracks(old).cloned().collect();
        let mut ids: HashMap<Id, Id> = HashMap::new();
        for t in &sources {
            let made = self.new_id();
            ids.insert(t.id, made);
        }
        let copies: Vec<Arc<Track>> = sources.iter().map(|t| Arc::new(self.copy_track(t, id, &ids))).collect();
        let nest = Nest {
            id,
            name,
            master: ids[&held.master],
            source: None,
            origin: held.source.clone().or_else(|| held.origin.clone()),
            ..(*held).clone()
        };
        let mut candidate = self.project.clone();
        candidate.tracks.extend(copies);
        candidate.nests.insert(id, Arc::new(nest));
        for t in candidate.tracks.iter_mut() {
            if !t.clips.iter().chain(&t.cues).any(|c| ours.contains(&c.id)) {
                continue;
            }
            let t = Arc::make_mut(t);
            for c in t.clips.iter_mut().chain(t.cues.iter_mut()).filter(|c| ours.contains(&c.id)) {
                if let ClipContent::Nest { nest, play, .. } = &mut Arc::make_mut(c).content {
                    *nest = id;
                    if let NestPlay::Track(track) = play {
                        *track = ids.get(track).copied().unwrap_or(*track);
                    }
                }
            }
        }
        candidate.validate()?;
        self.edit(|p| {
            *p = candidate;
            Ok(id)
        })
    }

    /// Copies of a track's devices and lanes, with new ids: a lane of a
    /// device follows its copy, and the side-chains and output pairs of the
    /// devices go to the tracks `tracks` names (by old id), else stay.
    pub(in crate::session) fn copy_devices_and_lanes(&mut self, t: &Track, tracks: &HashMap<Id, Id>) -> (Vec<Arc<DeviceInst>>, Vec<Arc<Lane>>) {
        let track = |id: Id| tracks.get(&id).copied().unwrap_or(id);
        let mut ids: HashMap<Id, Id> = HashMap::new();
        let devices = t
            .devices
            .iter()
            .map(|d| {
                let made = DeviceInst {
                    id: self.new_id(),
                    sidechain: d.sidechain.map(track),
                    outputs: d.outputs.iter().map(|(k, o)| (*k, track(*o))).collect(),
                    ..(**d).clone()
                };
                ids.insert(d.id, made.id);
                Arc::new(made)
            })
            .collect();
        let device = |id: Id| ids.get(&id).copied().unwrap_or(id);
        let lanes = t
            .lanes
            .iter()
            .map(|l| {
                let target = match &l.target {
                    Target::Param { device: d, param } => Target::Param { device: device(*d), param: param.clone() },
                    Target::State { device: d } => Target::State { device: device(*d) },
                    other => other.clone(),
                };
                Arc::new(Lane { id: self.new_id(), target, ..(**l).clone() })
            })
            .collect();
        (devices, lanes)
    }

    /// A copy of a nest's track for the nest `nest`, with the new track ids
    /// `ids` (by old id), and new ids for its devices, lanes and clips. Its
    /// routes to tracks of the nest follow the copies.
    fn copy_track(&mut self, t: &Track, nest: NestId, ids: &HashMap<Id, Id>) -> Track {
        let map = |id: Id| ids.get(&id).copied().unwrap_or(id);
        let mut copy = t.clone();
        copy.id = map(t.id);
        copy.nest = Some(nest);
        copy.output = t.output.map(map);
        for s in copy.sends.iter_mut() {
            s.target = map(s.target);
        }
        (copy.devices, copy.lanes) = self.copy_devices_and_lanes(t, ids);
        copy.chain = t.chain.as_ref().map(|g| Arc::new(self.copy_chain(g, &t.devices, &copy.devices)));
        copy.clips = t.clips.iter().map(|c| Arc::new(Clip { id: self.new_id(), ..(**c).clone() })).collect();
        copy.cues = t.cues.iter().map(|c| Arc::new(Clip { id: self.new_id(), ..(**c).clone() })).collect();
        if let Some(group) = t.meta.get("group").and_then(Value::as_u64) {
            copy.meta.insert("group".into(), json!(map(group)));
        }
        copy.source = None;
        copy.origin = t.source.clone().or_else(|| t.origin.clone());
        copy
    }
}
