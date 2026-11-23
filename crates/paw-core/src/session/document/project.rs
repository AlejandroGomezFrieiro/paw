//! The project's own fields: its name, tempo, signature, key, meta and
//! export settings.
//! Opening and saving the project is the session's, in
//! `session/project.rs`.

use std::path::Path;

use anyhow::{Result, bail};
use serde_json::{Value, json};

use super::Document;
use crate::session::{de, de_meta, holds};

impl Document {
    /// The project's fields as a table. `path` is the project's file, which
    /// the session knows.
    pub(crate) fn project_view(&self, path: Option<&Path>) -> Value {
        let p = &self.project;
        json!({
            "name": p.name, "tempo": p.tempo, "sig_num": p.sig_num, "sig_den": p.sig_den,
            "tempo_ramp": p.tempo_ramp, "tempo_changes": p.tempo_changes, "sig_changes": p.sig_changes,
            "key": p.key, "path": path, "length": p.end(), "meta": p.meta, "export": p.export,
            "modified": self.undo.touched || !self.undo.history.at_saved(),
            // Goes up with every change: compare two readings to see whether
            // something in between edited the project.
            "edits": self.changes(),
            // The same tempo and signature points give the same stamp.
            "tempo_stamp": p.tempo_stamp(),
        })
    }

    /// One entry of [`project_view`](Self::project_view), made alone: its
    /// `length` looks at every clip, and its `meta` can be large.
    pub(crate) fn project_field(&self, key: &str, path: Option<&Path>) -> Value {
        let p = &self.project;
        match key {
            "edits" => json!(self.changes()),
            "tempo_stamp" => json!(p.tempo_stamp()),
            "name" => json!(p.name),
            "tempo" => json!(p.tempo),
            "sig_num" => json!(p.sig_num),
            "sig_den" => json!(p.sig_den),
            "key" => json!(p.key),
            "export" => json!(p.export),
            "path" => json!(path),
            "modified" => json!(self.undo.touched || !self.undo.history.at_saved()),
            _ => self.project_view(path).get(key).cloned().unwrap_or(Value::Null),
        }
    }

    /// Set the project's field `key` to `value`. A value that it already
    /// holds is no change.
    pub(crate) fn project_set(&mut self, key: &str, value: Value, path: Option<&Path>) -> Result<()> {
        if holds(&Ok(self.project_view(path)), key, &value) {
            return Ok(());
        }
        let field: ProjectField = key.parse()?;
        self.edit(|p| {
            match field {
                ProjectField::Name => p.name = de(key, value)?,
                ProjectField::Tempo => {
                    let tempo: f64 = de(key, value)?;
                    if !(1.0..=999.0).contains(&tempo) {
                        bail!("tempo must be between 1 and 999");
                    }
                    let mut map = (**p.tempo_map()).clone();
                    map.set_first_tempo(tempo);
                    p.retime(map);
                }
                ProjectField::SigNum | ProjectField::SigDen => {
                    let n = de::<u32>(key, value)?.clamp(1, 64);
                    // A beat is a whole note halved some times: 3/3 has no note to count.
                    if field == ProjectField::SigDen && !n.is_power_of_two() {
                        bail!("a time signature's lower number is 1, 2, 4, 8, 16, 32 or 64, not {n}");
                    }
                    let (num, den) = if field == ProjectField::SigNum {
                        (n, p.sig_den)
                    } else {
                        (p.sig_num, n)
                    };
                    let mut map = (**p.tempo_map()).clone();
                    map.set_first_signature(num, den);
                    p.set_tempo_map(map);
                }
                ProjectField::Key => p.key = de(key, value)?,
                ProjectField::Meta => p.meta = de_meta(key, value)?,
                ProjectField::Export => p.export = de_meta(key, value)?,
            }
            Ok(())
        })
    }
}

/// A field of the project that [`Document::project_set`] changes: the key
/// that Lua gives, parsed once.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ProjectField {
    Name,
    Tempo,
    SigNum,
    SigDen,
    Key,
    Meta,
    Export,
}

impl std::str::FromStr for ProjectField {
    type Err = anyhow::Error;

    fn from_str(key: &str) -> Result<Self> {
        Ok(match key {
            "name" => Self::Name,
            "tempo" => Self::Tempo,
            "sig_num" => Self::SigNum,
            "sig_den" => Self::SigDen,
            "key" => Self::Key,
            "meta" => Self::Meta,
            "export" => Self::Export,
            _ => bail!("project has no settable field `{key}`"),
        })
    }
}
