//! The project's own fields: its name, tempo, signature, key, meta and
//! export settings.
//! Opening and saving the project is the session's, in
//! `session/project.rs`.

use std::path::Path;

use anyhow::{Result, bail};
use serde_json::{Map, Value};

use super::Document;
use super::values::{Lazy, patch, view};
use crate::model::{Project, SigChange, TempoChange};

view! {
    /// `paw.api.project_get()`.
    #[schemars(rename = "Project")]
    pub(crate) struct ProjectView<'a> {
        name: &'a str,
        /// Beats (quarter notes) per minute at the start of the song.
        tempo: f64,
        sig_num: u32,
        sig_den: u32,
        /// The tempo ramps from the start to the first tempo change.
        tempo_ramp: bool,
        tempo_changes: &'a [TempoChange],
        sig_changes: &'a [SigChange],
        /// The song's key, such as "D minor".
        key: Option<&'a str>,
        /// The project's file; nil before it is saved.
        path: Option<&'a Path>,
        /// The end of the last clip, in beats.
        length: Lazy<&'a Project, f64>,
        #[schemars(extend("x-teal" = "Meta"))]
        meta: &'a Map<String, Value>,
        #[schemars(extend("x-teal" = "ProjectExport"))]
        export: &'a Map<String, Value>,
        /// The project has changes that are not saved.
        modified: bool,
        /// Goes up with each change: compare two readings to see whether
        /// something in between edited the project.
        edits: u64,
        /// A hash of the tempo and signature points, the same for the same
        /// points (after an undo too).
        tempo_stamp: Lazy<&'a Project, u64>,
    }
}

patch! {
    /// What `paw.api.project_set` changes in the project: each field as
    /// `project_get` gives it, and what is left out stays.
    #[schemars(rename = "ProjectChanges")]
    pub(crate) struct ProjectPatch => ProjectChange, "the project has no settable field" {
        /// The project's export presets by name.
        #[schemars(extend("x-teal" = "ProjectExport"))]
        "export" export: Map<String, Value> => Export default,
        /// The song's key, such as "D minor"; nil for none.
        "key" key: String => Key clear,
        #[schemars(extend("x-teal" = "Meta"))]
        "meta" meta: Map<String, Value> => Meta default,
        "name" name: String => Name value,
        /// The lower number of the time signature at the start: 1, 2, 4,
        /// 8, 16, 32 or 64.
        "sig_den" sig_den: u32 => SigDen value,
        /// The upper number of the time signature at the start, 1 to 64.
        "sig_num" sig_num: u32 => SigNum value,
        /// The tempo at the start, from 1 to 999 beats per minute.
        "tempo" tempo: f64 => Tempo value,
    }
}

impl Document {
    /// The project's fields as a table. `path` is the project's file, which
    /// the session knows.
    pub(crate) fn project_view<'a>(&'a self, path: Option<&'a Path>) -> ProjectView<'a> {
        let p = &self.project;
        ProjectView {
            name: &p.name,
            tempo: p.tempo,
            sig_num: p.sig_num,
            sig_den: p.sig_den,
            tempo_ramp: p.tempo_ramp,
            tempo_changes: &p.tempo_changes,
            sig_changes: &p.sig_changes,
            key: p.key.as_deref(),
            path,
            length: Lazy::new(p, |p| p.end()),
            meta: &p.meta,
            export: &p.export,
            modified: self.undo.touched || !self.undo.history.at_saved(),
            edits: self.changes(),
            tempo_stamp: Lazy::new(p, |p| p.tempo_stamp()),
        }
    }

    /// Make one change of the project. A value that it already holds is no
    /// change.
    pub(crate) fn project_set(&mut self, change: ProjectChange) -> Result<()> {
        if change.holds(&self.project) {
            return Ok(());
        }
        self.edit(|p| {
            match change {
                ProjectChange::Name(name) => p.name = name,
                ProjectChange::Tempo(tempo) => {
                    if !(1.0..=999.0).contains(&tempo) {
                        bail!("tempo must be between 1 and 999");
                    }
                    let mut map = (**p.tempo_map()).clone();
                    map.set_first_tempo(tempo);
                    p.retime(map);
                }
                ProjectChange::SigNum(num) => {
                    let mut map = (**p.tempo_map()).clone();
                    map.set_first_signature(num.clamp(1, 64), p.sig_den);
                    p.set_tempo_map(map);
                }
                ProjectChange::SigDen(den) => {
                    let den = den.clamp(1, 64);
                    // A beat is a whole note halved some times: 3/3 has no note to count.
                    if !den.is_power_of_two() {
                        bail!("a time signature's lower number is 1, 2, 4, 8, 16, 32 or 64, not {den}");
                    }
                    let mut map = (**p.tempo_map()).clone();
                    map.set_first_signature(p.sig_num, den);
                    p.set_tempo_map(map);
                }
                ProjectChange::Key(key) => p.key = key,
                ProjectChange::Meta(meta) => p.meta = meta,
                ProjectChange::Export(export) => p.export = export,
            }
            Ok(())
        })
    }
}

impl ProjectChange {
    /// Project `p` already holds what the change gives.
    #[expect(clippy::float_cmp, reason = "an unchanged value makes no undo step")]
    fn holds(&self, p: &Project) -> bool {
        match self {
            Self::Name(name) => p.name == *name,
            Self::Tempo(tempo) => p.tempo == *tempo,
            Self::SigNum(num) => p.sig_num == *num,
            Self::SigDen(den) => p.sig_den == *den,
            Self::Key(key) => p.key == *key,
            Self::Meta(meta) => p.meta == *meta,
            Self::Export(export) => p.export == *export,
        }
    }
}
