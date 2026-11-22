//! Nests (subprojects): make one, read one, change one. Each change is one
//! undo step. The model and its rules are in `model/nest.rs`; the files in
//! `folder/nests.rs`.

use super::*;
use crate::model::{Nest, NestId, NestMeter, NestTempo};

/// The length of a nest made with none: 8 bars of 4/4.
const DEFAULT_LENGTH: f64 = 32.0;

/// What `paw.api.nest_add` takes.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct NestOpts {
    pub name: Option<String>,
    /// Beats; 32 when absent.
    pub length: Option<f64>,
    pub tempo: Option<NestTempo>,
    pub meter: Option<NestMeter>,
    pub kind: Option<String>,
    pub meta: Option<Value>,
}

/// A field of a nest that [`Session::nest_set`] changes.
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

impl Session {
    /// Make a nest with its master track and no other track. Returns its id.
    pub fn nest_add(&mut self, opts: NestOpts) -> Result<NestId> {
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
    pub fn nest_view(&self, id: NestId) -> Result<Value> {
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
    /// [`Session::nest_view`], which looks at every clip.
    pub fn nest_field(&self, id: NestId, key: &str) -> Result<Value> {
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
    pub fn nest_list(&self) -> Vec<NestId> {
        self.project.nests.keys().copied().collect()
    }

    /// Change one field of a nest. A value that is as it was is no change.
    /// A new tempo keeps the song's blocks of the nest on the beats of the
    /// nest they play: their length in the song follows it.
    pub fn nest_set(&mut self, id: NestId, key: &str, value: Value) -> Result<()> {
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
