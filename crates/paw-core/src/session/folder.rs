//! A project as a folder of files.
//!
//! ```text
//! song/
//! ├── project.toml            the tempo, the meter, the order of the parts
//! ├── meta.json               the project's `meta`, when it has some
//! ├── racks.json              the definitions of the linked racks, when it has some
//! ├── screen.json             the tabs and windows it opens with
//! ├── .gitattributes          `*.midi2 diff=paw-midi2`
//! ├── master/                 the master part, as a part folder
//! ├── parts/<name>/
//! │   ├── part.json          the part and its clips, without their notes
//! │   ├── devices.json        the chain and its parameters
//! │   ├── <n>-<kind>.state    a plugin's state, as the plugin gives it
//! │   ├── automation/<target>.json
//! │   ├── clips/<name>.midi2  a MIDI 2.0 clip file (crate::clipfile)
//! │   └── clips/<name>.<kind>.json, .signals.json, .sound.midi2
//! │                           the parts of a custom clip (`Writer::custom_clip`)
//! ├── media.json              what each file the clips use is: hash, size, header
//! ├── media/                  sound files, and `derived/` for those a kind makes
//! ├── nests/<name>/           a nest (subproject): see `folder/nests.rs`
//! ├── linked/<link>.midi2     the notes of each link of clips (`model/links.rs`)
//! └── unused/                 files the project does not use any more, and
//!                             `unused/nests/`, the nests no clip places
//! ```
//!
//! [`layout`] turns a project into the bytes of each file, [`commit`]
//! writes the files that changed and moves those the project no longer
//! uses to `unused/` at the same path, and [`read`] puts the project
//! together again. The JSON files are written with their keys in order, so
//! the same project gives the same bytes.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::cast_precision_loss, reason = "debt: pay down"))]

use crate::events::{KernelEvent as E, Saved};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use serde_json::{Map, Value, json};

use super::BASE64;
use super::media::MEDIA_FILE;
use super::project_files::{DiskFiles, MemoryFiles, ProjectFiles};
use crate::clipfile;
use crate::model::{Chain, Clip, ClipContent, Control, KindData, Notes, Project, Target, Part};

mod nests;
pub(crate) mod old_meta;
pub(super) use nests::read_nested;

/// The file that makes a folder a project.
pub(crate) const PROJECT_FILE: &str = "project.toml";
/// The version of the folder's format.
const VERSION: u32 = 2;
/// The folders and the files at the top of a project that paw writes, and
/// so may move to `unused/` when the project does not need them.
const MANAGED_DIRS: [&str; 4] = ["parts", "master", "nests", LINKED_DIR];
/// The folder of the notes of each link: one file for all of its clips.
const LINKED_DIR: &str = "linked";
const MANAGED_FILES: [&str; 4] = ["meta.json", "racks.json", "screen.json", MEDIA_FILE];
const GITATTRIBUTES: &str = "*.midi2 diff=paw-midi2\n";

/// Whether a path names a project kept as a folder: a folder, its
/// `project.toml`, or a name with no extension that is not a file yet.
/// Anything else is a project in one JSON file.
pub(crate) fn is_folder_path(path: &Path) -> bool {
    path.file_name().is_some_and(|n| n == PROJECT_FILE)
        || path.is_dir()
        || (!path.exists() && path.extension().is_none())
}

/// Whether `rel`, a path in a project folder, is one of the files that paw
/// writes there: the project file, the files at the top that it manages,
/// and everything under `parts/` and `master/`.
pub(crate) fn is_managed(rel: &Path) -> bool {
    rel.as_os_str() == PROJECT_FILE
        || MANAGED_FILES.iter().any(|f| rel.as_os_str() == *f)
        || rel
            .components()
            .next()
            .is_some_and(|c| MANAGED_DIRS.iter().any(|d| c.as_os_str() == *d))
}

/// The project file as it was before the last save that changed it.
pub(crate) fn backup_of(dir: &Path) -> PathBuf {
    dir.join(format!("{PROJECT_FILE}.bak"))
}

/// The `project.toml` of a project folder named by itself or by that file.
pub(crate) fn project_file(path: &Path) -> PathBuf {
    if path.file_name().is_some_and(|n| n == PROJECT_FILE) {
        path.to_path_buf()
    } else {
        path.join(PROJECT_FILE)
    }
}

/// A name made of letters, digits, `-`, `_` and `.`, for a file or a
/// folder, that does not start with a dot.
pub(crate) fn file_name(name: &str) -> String {
    let safe: String = name
        .trim()
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' || c == '.' {
                c
            } else {
                '-'
            }
        })
        .collect();
    let safe = safe.trim_start_matches('.').to_string();
    if safe.is_empty() {
        "unnamed".into()
    } else {
        safe
    }
}

/// A name from `stem` not in `taken` (`riff`, `riff-2`, ...), now taken.
/// `taken` holds lowercase names: two names that differ only in case are
/// one file on some disks.
fn unique(taken: &mut BTreeSet<String>, stem: &str, ext: &str) -> String {
    let name = crate::names::free(|n| taken.contains(&n.to_lowercase()), stem, ext, crate::names::Scheme::Dash);
    taken.insert(name.to_lowercase());
    name
}

/// The files of a project, by their path in its folder.
#[derive(Default)]
pub(crate) struct Layout {
    pub files: BTreeMap<PathBuf, Vec<u8>>,
    /// The file each clip's notes are in, by clip id: a path in the folder,
    /// or a file outside it the clip refers to.
    pub clip_files: HashMap<u64, PathBuf>,
    /// The folder of each part, by part id.
    pub part_folders: HashMap<u64, PathBuf>,
}

fn pretty(value: &Value) -> Vec<u8> {
    let mut text = serde_json::to_string_pretty(value).unwrap_or_default();
    text.push('\n');
    text.into_bytes()
}

/// `value` as TOML, without the nulls TOML has no word for.
fn to_toml(value: &Value) -> Option<toml::Value> {
    Some(match value {
        Value::Null => return None,
        Value::Bool(b) => toml::Value::Boolean(*b),
        Value::Number(n) => match n.as_i64() {
            Some(i) => toml::Value::Integer(i),
            None => toml::Value::Float(n.as_f64()?),
        },
        Value::String(s) => toml::Value::String(s.clone()),
        Value::Array(list) => toml::Value::Array(list.iter().filter_map(to_toml).collect()),
        Value::Object(map) => toml::Value::Table(
            map.iter()
                .filter_map(|(k, v)| Some((k.clone(), to_toml(v)?)))
                .collect(),
        ),
    })
}

fn from_toml(value: toml::Value) -> Value {
    match value {
        toml::Value::String(s) => Value::String(s),
        toml::Value::Integer(i) => json!(i),
        toml::Value::Float(f) => json!(f),
        toml::Value::Boolean(b) => Value::Bool(b),
        toml::Value::Datetime(d) => Value::String(d.to_string()),
        toml::Value::Array(list) => Value::Array(list.into_iter().map(from_toml).collect()),
        toml::Value::Table(map) => {
            Value::Object(map.into_iter().map(|(k, v)| (k, from_toml(v))).collect())
        }
    }
}

/// A lane's file name, from what it automates.
fn lane_stem(target: &Target, part: &Part) -> String {
    match target {
        Target::Volume => "volume".into(),
        Target::Pan => "pan".into(),
        Target::Param { device, param } => {
            let device = part
                .devices
                .iter()
                .position(|d| d.id == *device)
                .map(|i| {
                    let d = &part.devices[i];
                    format!("{}-{}", i + 1, d.name.as_deref().unwrap_or(&d.kind))
                })
                .unwrap_or_else(|| device.to_string());
            file_name(&format!("{device}-{param}"))
        }
        Target::State { device } => {
            let device = part
                .devices
                .iter()
                .position(|d| d.id == *device)
                .map(|i| {
                    let d = &part.devices[i];
                    format!("{}-{}", i + 1, d.name.as_deref().unwrap_or(&d.kind))
                })
                .unwrap_or_else(|| device.to_string());
            file_name(&format!("{device}-state"))
        }
    }
}

/// A clip as `part.json` holds it: everything but its notes, which are in
/// the file it names.
fn clip_entry(clip: &Clip, file: Option<&Path>) -> Result<Value> {
    let mut bare = clip.clone();
    if let ClipContent::Midi { notes, controls } = &mut bare.content {
        *notes = Notes::new();
        controls.clear();
    }
    // Where the notes are is the entry's `file`.
    bare.source = None;
    let mut value = serde_json::to_value(&bare)?;
    if let (Some(file), Some(content)) = (file, value.get_mut("content")) {
        *content = json!({ "kind": "midi", "file": file });
    }
    Ok(value)
}

struct Writer<'a> {
    layout: Layout,
    /// The file that holds each set of clip bytes already written: repeats
    /// of a part share one.
    written: HashMap<Vec<u8>, PathBuf>,
    dir: &'a Path,
    home: &'a Home,
}

impl Writer<'_> {
    fn part(&mut self, part: &Part, folder: &Path) -> Result<()> {
        self.layout
            .part_folders
            .insert(part.id, folder.to_path_buf());
        let mut taken = BTreeSet::new();
        let mut entry = part.clone();
        entry.devices = Vec::new();
        entry.clips = Default::default();
        entry.lanes = Vec::new();
        entry.cues = Default::default();
        let mut value = serde_json::to_value(&entry)?;
        let mut clips = Vec::new();
        for clip in &part.clips {
            clips.push(self.clip(clip, folder, &mut taken)?);
        }
        let mut cues = Vec::new();
        for clip in &part.cues {
            cues.push(self.clip(clip, folder, &mut taken)?);
        }
        // A chain kept in a file outside the folder: named, not written.
        let outside_chain = part.chain_source.as_ref().map(|f| self.home.outside_name(f, self.dir));
        let mut devices = Vec::new();
        if outside_chain.is_none() {
            let (chain, states) = chain_files(part)?;
            devices = chain;
            for (name, bytes) in states {
                self.layout.files.insert(folder.join(name), bytes);
            }
        }
        let mut lanes = Vec::new();
        let mut lane_names = BTreeSet::new();
        for lane in &part.lanes {
            let name = unique(&mut lane_names, &lane_stem(&lane.target, part), ".json");
            let rel = Path::new("automation").join(&name);
            self.layout
                .files
                .insert(folder.join(&rel), pretty(&serde_json::to_value(&**lane)?));
            lanes.push(json!(rel));
        }
        let map = value.as_object_mut().context("a part")?;
        for key in ["devices", "clips", "lanes", "cues"] {
            map.remove(key);
        }
        map.insert("clips".into(), Value::Array(clips));
        if !cues.is_empty() {
            map.insert("cues".into(), Value::Array(cues));
        }
        if !lanes.is_empty() {
            map.insert("lanes".into(), Value::Array(lanes));
        }
        // The folder a part is in says which nest it belongs to.
        for key in ["source", "chain_source", "nest"] {
            map.remove(key);
        }
        if let Some(chain) = &outside_chain {
            map.insert("devices_file".into(), json!(chain));
        }
        self.layout
            .files
            .insert(folder.join("part.json"), pretty(&value));
        if outside_chain.is_none() {
            self.layout
                .files
                .insert(folder.join("devices.json"), pretty(&Value::Array(devices)));
        }
        Ok(())
    }

    /// Write parts in order, each in `<root>/parts/<name>`, and give the
    /// list of their folders' names as `project.toml` and `nest.toml` keep
    /// it: a part folder outside the project is named by its path.
    fn parts<'t>(
        &mut self,
        parts: impl Iterator<Item = &'t Arc<Part>>,
        root: &Path,
        mut cache: Option<&mut PartCache>,
    ) -> Result<Vec<String>> {
        let mut folders = BTreeSet::new();
        let mut order = Vec::new();
        for part in parts {
            if let Some(source) = &part.source {
                // A part folder outside the project: the project names it and
                // writes nothing of it.
                for clip in part.clips.iter().chain(&part.cues) {
                    if let Some(file) = &clip.source {
                        self.layout.clip_files.insert(clip.id, file.clone());
                    }
                }
                order.push(self.home.outside_name(source, self.dir).to_string_lossy().into_owned());
                continue;
            }
            let name = unique(&mut folders, &file_name(&part.name), "");
            let folder = root.join("parts").join(&name);
            match cache.as_deref_mut() {
                Some(cache) => cache.part(self, part, &folder)?,
                None => self.part(part, &folder)?,
            }
            order.push(name);
        }
        Ok(order)
    }

    fn clip(&mut self, clip: &Clip, folder: &Path, taken: &mut BTreeSet<String>) -> Result<Value> {
        let ClipContent::Midi { notes, controls } = &clip.content else {
            if let ClipContent::Custom(_) = &clip.content {
                return self.custom_clip(clip, folder, taken);
            }
            return self.audio_clip(clip, folder, taken);
        };
        // A clip that refers to a file outside goes on referring to it.
        if let Some(source) = &clip.source {
            let file = self.home.outside_name(source, self.dir);
            self.layout.clip_files.insert(clip.id, source.clone());
            return clip_entry(clip, Some(&file));
        }
        if let Some(link) = &clip.link {
            return self.linked_clip(clip, link, notes, controls);
        }
        let bytes = clipfile::encode(notes.iter(), controls, clip.length)
            .with_context(|| format!("writing clip {}", clip.id))?;
        let path = match self.written.get(&bytes) {
            Some(path) => path.clone(),
            None => {
                let stem = file_name(if clip.name.is_empty() {
                    "clip"
                } else {
                    &clip.name
                });
                let name = unique(taken, &stem, ".midi2");
                let path = folder.join("clips").join(name);
                self.written.insert(bytes.clone(), path.clone());
                self.layout.files.insert(path.clone(), bytes);
                path
            }
        };
        self.layout.clip_files.insert(clip.id, path.clone());
        clip_entry(clip, Some(&path))
    }
}

impl Writer<'_> {
    /// A clip of a link: its entry names the link's file, `linked/<link>.midi2`,
    /// which every clip of the link names. The file has no length of its
    /// own: the clips of a link may each be of another length, and each
    /// part writes the file alone in the undo file (`PartCache`), so the
    /// bytes come from the notes and the controller moves only.
    fn linked_clip(&mut self, clip: &Clip, link: &str, notes: &Notes, controls: &[Control]) -> Result<Value> {
        let path = Path::new(LINKED_DIR).join(format!("{link}.midi2"));
        if !self.layout.files.contains_key(&path) {
            let bytes = clipfile::encode(notes.iter(), controls, 0.0)
                .with_context(|| format!("writing the linked clip {link}"))?;
            self.layout.files.insert(path.clone(), bytes);
        }
        self.layout.clip_files.insert(clip.id, path.clone());
        clip_entry(clip, Some(&path))
    }
}

/// The `.state` files of a chain's plugins: each file's name and bytes.
type StateFiles = Vec<(String, Vec<u8>)>;

/// A part's chain as a `devices.json` holds it, and the `.state` file of
/// each plugin's state that it names, by name.
fn chain_files(part: &Part) -> Result<(Vec<Value>, StateFiles)> {
    let mut devices = Vec::new();
    let mut files = Vec::new();
    let mut states = BTreeSet::new();
    for (i, device) in part.devices.iter().enumerate() {
        let mut d = serde_json::to_value(&**device)?;
        if let Some(state) = device.state.as_deref() {
            let bytes = BASE64
                .decode(state)
                .with_context(|| format!("the state of device {}", device.id))?;
            let name = unique(&mut states, &file_name(&format!("{}-{}", i + 1, device.kind)), ".state");
            d.as_object_mut().map(|o| o.remove("state"));
            d["state_file"] = json!(name);
            files.push((name, bytes));
        }
        // The files the device keeps beside its state, each named after it.
        let mut names = serde_json::Map::new();
        for (key, text) in &device.files {
            let bytes = BASE64
                .decode(text)
                .with_context(|| format!("the {key} file of device {}", device.id))?;
            let stem = file_name(&format!("{}-{}", i + 1, device.kind));
            let name = unique(&mut states, &stem, &format!(".{}", file_name(key)));
            names.insert(key.clone(), json!(name));
            files.push((name, bytes));
        }
        if !names.is_empty() {
            d.as_object_mut().map(|o| o.remove("files"));
            d["file_names"] = Value::Object(names);
        }
        devices.push(d);
    }
    Ok((devices, files))
}

impl Writer<'_> {
    /// An audio clip as `part.json` holds it. Its edit list, when it has
    /// one, is a file of its own (`clips/<name>.edits.json`), which the entry
    /// names as `edits_file`: pencil fixes hold many samples.
    fn audio_clip(&mut self, clip: &Clip, folder: &Path, taken: &mut BTreeSet<String>) -> Result<Value> {
        let mut value = clip_entry(clip, None)?;
        let Some(edits) = value.get_mut("content").and_then(|c| c.as_object_mut()).and_then(|c| c.remove("edits")) else {
            return Ok(value);
        };
        let stem = file_name(if clip.name.is_empty() { "clip" } else { &clip.name });
        let path = folder.join("clips").join(unique(taken, &stem, ".edits.json"));
        self.layout.files.insert(path.clone(), pretty(&edits));
        value["content"]["edits_file"] = json!(path);
        Ok(value)
    }
}

impl Writer<'_> {
    /// The file for `bytes` in the part's `clips/`: named `<stem><middle>.<ext>`,
    /// and shared by every clip with the same bytes (a split clip keeps its
    /// data, so both halves name one file).
    fn clip_file(
        &mut self,
        folder: &Path,
        taken: &mut BTreeSet<String>,
        stem: &str,
        middle: &str,
        ext: &str,
        bytes: Vec<u8>,
    ) -> PathBuf {
        let ext = format!(".{ext}");
        // The same bytes under another name or kind are another file.
        let mut key = format!("{middle}{ext}\0").into_bytes();
        key.extend_from_slice(&bytes);
        if let Some(path) = self.written.get(&key) {
            return path.clone();
        }
        let name = unique(taken, &format!("{stem}{middle}"), &ext);
        let path = folder.join("clips").join(name);
        self.written.insert(key, path.clone());
        self.layout.files.insert(path.clone(), bytes);
        path
    }

    /// A custom clip as `part.json` holds it. Its data, its signals and its
    /// sound when that is MIDI are files of their own in `clips/`, named by
    /// the entry (`data.json_file`, `data.text_file`, `signals_file`,
    /// `sound.file`): JSON data is pretty with sorted keys and text data is
    /// as the kind wrote it, so a change reads in `git diff`, and the entry
    /// keeps the rest.
    fn custom_clip(&mut self, clip: &Clip, folder: &Path, taken: &mut BTreeSet<String>) -> Result<Value> {
        let ClipContent::Custom(custom) = &clip.content else {
            bail!("clip {} is not a custom clip", clip.id);
        };
        let mut value = clip_entry(clip, None)?;
        let stem = file_name(if clip.name.is_empty() { "clip" } else { &clip.name });
        let kind = format!(".{}", custom.kind);
        let (data, path) = match &custom.data {
            KindData::Json(json) => {
                let bytes = pretty(json.get());
                let path = self.clip_file(folder, taken, &stem, &kind, "json", bytes);
                (json!({ "json_file": path }), path)
            }
            KindData::Text { ext, text } => {
                let bytes = text.as_bytes().to_vec();
                let path = self.clip_file(folder, taken, &stem, &kind, ext.as_str(), bytes);
                (json!({ "text_file": path, "ext": ext }), path)
            }
        };
        self.layout.clip_files.insert(clip.id, path);
        let content = value
            .get_mut("content")
            .and_then(Value::as_object_mut)
            .context("a custom clip")?;
        content.insert("data".into(), data);
        if !custom.signals.is_empty() {
            let bytes = pretty(&serde_json::to_value(&*custom.signals)?);
            let path = self.clip_file(folder, taken, &stem, ".signals", "json", bytes);
            content.remove("signals");
            content.insert("signals_file".into(), json!(path));
        }
        if let Some(ClipContent::Midi { notes, controls }) = custom.sound.as_ref().map(|s| s.content()) {
            let bytes = clipfile::encode(notes.iter(), controls, clip.length)
            .with_context(|| format!("writing clip {}", clip.id))?;
            let path = self.clip_file(folder, taken, &stem, ".sound", "midi2", bytes);
            content.insert("sound".into(), json!({ "kind": "midi", "file": path }));
        }
        Ok(value)
    }
}

/// The home folder that `~/` names in a project's files. The program finds
/// it once at its start and gives it to the session (`KernelOpts::home`),
/// so that the library code does not read `HOME`. With no home folder, a
/// path outside the project stays absolute and a `~/` path stays as it is.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Home(Option<PathBuf>);

impl Home {
    /// The home folder at `path`, or no home folder.
    pub(crate) fn new(path: Option<PathBuf>) -> Self {
        Self(path)
    }

    /// How a project in the folder `dir` names a file: from `dir` when it
    /// is in it, from the home folder as `~/...` when it is there, else by
    /// the absolute path.
    fn outside_name(&self, file: &Path, dir: &Path) -> PathBuf {
        if let Ok(rel) = file.strip_prefix(dir) {
            return rel.to_path_buf();
        }
        if let Some(home) = &self.0
            && let Ok(rel) = file.strip_prefix(home)
        {
            return Path::new("~").join(rel);
        }
        file.to_path_buf()
    }

    /// A path as a project file in the folder `dir` gives it, made
    /// absolute: `~/` from the home folder, a relative one from `dir`.
    pub(crate) fn resolve(&self, file: &Path, dir: &Path) -> PathBuf {
        if let Ok(rel) = file.strip_prefix("~")
            && let Some(home) = &self.0
        {
            return home.join(rel);
        }
        if file.is_absolute() {
            file.to_path_buf()
        } else {
            tidy(&dir.join(file))
        }
    }
}

pub(crate) fn tidy(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                if !out.pop() {
                    out.push("..");
                }
            }
            other => out.push(other),
        }
    }
    out
}

/// The files of a project in the folder `dir`. Its media paths are already
/// as the folder names them (see `media::for_file`).
pub(crate) fn layout(
    project: &Project,
    transport: &Value,
    screen: Option<&Value>,
    dir: &Path,
    home: &Home,
) -> Result<Layout> {
    lay_out(project, transport, screen, dir, home, None)
}

/// The files of each part laid out alone, kept from one [`layout_cached`]
/// to the next: states of the undo tree share most of their parts.
#[derive(Default)]
pub(crate) struct PartCache {
    now: HashMap<(usize, PathBuf), CachedPart>,
    before: HashMap<(usize, PathBuf), CachedPart>,
}

struct CachedPart {
    /// Keeps the part, so that no other part gets its address.
    _part: Arc<Part>,
    files: Vec<(PathBuf, Vec<u8>)>,
}

impl PartCache {
    /// Put the files of `part` in `folder` into `w`'s layout: from the
    /// cache when the last layout had the very same part there.
    fn part(&mut self, w: &mut Writer<'_>, part: &Arc<Part>, folder: &Path) -> Result<()> {
        let key = (Arc::as_ptr(part) as usize, folder.to_path_buf());
        let entry = match self.now.remove(&key).or_else(|| self.before.remove(&key)) {
            Some(entry) => entry,
            None => {
                // Alone: no file is shared with another part, so the files
                // stay right whatever the other parts become.
                let mut alone = Writer { layout: Layout::default(), written: HashMap::new(), dir: w.dir, home: w.home };
                alone.part(part, folder)?;
                CachedPart { _part: Arc::clone(part), files: alone.layout.files.into_iter().collect() }
            }
        };
        for (path, bytes) in &entry.files {
            w.layout.files.insert(path.clone(), bytes.clone());
        }
        w.layout.part_folders.insert(part.id, folder.to_path_buf());
        self.now.insert(key, entry);
        Ok(())
    }
}

/// The files of a project as [`layout`] gives them, except that no two
/// parts share a file and `clip_files` is empty: for the states of the undo
/// file, which read back as the same project. The parts that the last call
/// laid out come from `cache`.
pub(crate) fn layout_cached(
    project: &Project,
    transport: &Value,
    screen: Option<&Value>,
    dir: &Path,
    home: &Home,
    cache: &mut PartCache,
) -> Result<Layout> {
    cache.before = std::mem::take(&mut cache.now);
    lay_out(project, transport, screen, dir, home, Some(cache))
}

fn lay_out(
    project: &Project,
    transport: &Value,
    screen: Option<&Value>,
    dir: &Path,
    home: &Home,
    mut cache: Option<&mut PartCache>,
) -> Result<Layout> {
    let mut w = Writer {
        layout: Layout::default(),
        written: HashMap::new(),
        dir,
        home,
    };
    let order = w.parts(project.song_parts(), Path::new(""), cache.as_deref_mut())?;
    match cache {
        Some(cache) => cache.part(&mut w, &project.master, Path::new("master"))?,
        None => w.part(&project.master, Path::new("master"))?,
    }
    let nests = w.nests(project)?;
    let mut bare = project.clone();
    bare.master = Arc::new(Part::new(0));
    bare.parts = Vec::new();
    bare.nests = BTreeMap::new();
    bare.meta = Map::new();
    bare.racks = Default::default();
    let mut head = serde_json::to_value(&bare)?;
    let map = head.as_object_mut().context("a project")?;
    map.remove("master");
    map.remove("parts");
    map.remove("meta");
    map.insert("version".into(), json!(VERSION));
    map.insert("parts".into(), json!(order));
    if !nests.is_empty() {
        map.insert("nests".into(), json!(nests));
    }
    map.insert("transport".into(), transport.clone());
    let head = to_toml(&head).context("a project")?;
    let mut text = toml::to_string_pretty(&head).context("writing project.toml")?;
    if !text.ends_with('\n') {
        text.push('\n');
    }
    w.layout
        .files
        .insert(PROJECT_FILE.into(), text.into_bytes());
    if !project.meta.is_empty() {
        w.layout.files.insert(
            "meta.json".into(),
            pretty(&Value::Object(project.meta.clone())),
        );
    }
    if !project.racks.is_empty() {
        w.layout.files.insert(
            "racks.json".into(),
            pretty(&serde_json::to_value(&project.racks)?),
        );
    }
    if let Some(screen) = screen {
        w.layout.files.insert("screen.json".into(), pretty(screen));
    }
    Ok(w.layout)
}

/// What a save did to the files.
#[derive(Debug, Default)]
pub(crate) struct Committed {
    /// Paths in the folder that were written, `project.toml` last.
    pub written: Vec<PathBuf>,
    /// Those that were the same already.
    pub unchanged: usize,
    /// Files moved in the folder, as a renamed part's are: (from, to).
    pub moved: Vec<(PathBuf, PathBuf)>,
    /// Files the project does not use any more, now in `unused/`.
    pub unused: Vec<PathBuf>,
}

/// Every file under the folders paw writes, by its path in the folder.
fn managed_files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack: Vec<PathBuf> = MANAGED_DIRS.iter().map(PathBuf::from).collect();
    while let Some(rel) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(dir.join(&rel)) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = rel.join(entry.file_name());
            match entry.file_type() {
                Ok(t) if t.is_dir() => stack.push(path),
                Ok(_) => {
                    // A temporary file of a save cut short is not the user's.
                    if !path.to_string_lossy().ends_with(".paw-tmp") {
                        out.push(path);
                    }
                }
                Err(_) => {}
            }
        }
    }
    for name in MANAGED_FILES {
        if dir.join(name).is_file() {
            out.push(name.into());
        }
    }
    out.sort();
    out
}

fn tmp_of(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(".paw-tmp");
    PathBuf::from(name)
}

/// Run `f` on each item, on up to eight threads: flushes to the disk that
/// wait on each other less when they are asked for together.
fn in_parallel<T: Sync>(
    items: &[T],
    f: impl Fn(&T) -> std::io::Result<()> + Sync,
) -> std::io::Result<()> {
    let threads = std::thread::available_parallelism()
        .map_or(1, |n| n.get())
        .min(8);
    if items.len() < 8 || threads < 2 {
        return items.iter().try_for_each(&f);
    }
    let chunk = items.len().div_ceil(threads);
    std::thread::scope(|s| {
        let f = &f;
        let handles: Vec<_> = items
            .chunks(chunk)
            .map(|chunk| s.spawn(move || chunk.iter().try_for_each(f)))
            .collect();
        handles.into_iter().try_for_each(|h| {
            h.join()
                .unwrap_or_else(|_| Err(std::io::Error::other("a writer stopped")))
        })
    })
}

/// Flush directories' entries (the renames in them) to the disk.
fn sync_dirs(dirs: &BTreeSet<PathBuf>) {
    let list: Vec<&PathBuf> = dirs.iter().collect();
    let _ = in_parallel(&list, |d| {
        crate::safe::sync_dir(d);
        Ok(())
    });
}

/// A place in `unused/` for `rel` that nothing has yet.
fn unused_place(dir: &Path, rel: &Path) -> PathBuf {
    let base = Path::new("unused").join(rel);
    let mut place = base.clone();
    let mut n = 2;
    while dir.join(&place).exists() {
        let stem = base
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
        let ext = base
            .extension()
            .map(|e| format!(".{}", e.to_string_lossy()))
            .unwrap_or_default();
        place = base.with_file_name(format!("{stem}-{n}{ext}"));
        n += 1;
    }
    place
}

/// Write the files of `layout` into `dir` that are not there already as
/// they are, the project file last, each written in full beside its place
/// and then renamed over it, so a crash leaves each file old or new. Files
/// paw wrote that the project does not use any more go to `unused/`, or are
/// moved to where a file of the same bytes is wanted (a renamed part).
pub(crate) fn commit(dir: &Path, layout: &Layout, only: Option<&BTreeSet<PathBuf>>) -> Result<Committed> {
    std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
    let mut done = Committed::default();
    let before = managed_files(dir);
    let leaving: Vec<PathBuf> = if only.is_some() {
        Vec::new()
    } else {
        before
            .iter()
            .filter(|p| !layout.files.contains_key(*p))
            .cloned()
            .collect()
    };
    // Files that leave, by their bytes: one wanted elsewhere moves there.
    let mut by_bytes: HashMap<Vec<u8>, Vec<PathBuf>> = HashMap::new();
    for rel in &leaving {
        if let Ok(bytes) = std::fs::read(dir.join(rel)) {
            by_bytes.entry(bytes).or_default().push(rel.clone());
        }
    }
    let mut staged = Vec::new();
    let mut gone = BTreeSet::new();
    let wanted = |rel: &PathBuf| only.is_none_or(|o| o.contains(rel));
    for (rel, bytes) in layout.files.iter().filter(|(rel, _)| wanted(rel)) {
        let path = dir.join(rel);
        if std::fs::read(&path).is_ok_and(|old| &old == bytes) {
            done.unchanged += 1;
            continue;
        }
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("creating {}", parent.display()))?;
        }
        if !path.exists()
            && let Some(from) = by_bytes.get_mut(bytes).and_then(|list| list.pop())
        {
            std::fs::rename(dir.join(&from), &path)
                .with_context(|| format!("moving {} to {}", from.display(), rel.display()))?;
            gone.insert(from.clone());
            done.moved.push((from, rel.clone()));
            continue;
        }
        staged.push((rel.clone(), bytes));
    }
    // Each file in full on the disk beside its place before any is renamed.
    in_parallel(&staged, |(rel, bytes)| {
        use std::io::Write;
        let tmp = tmp_of(&dir.join(rel));
        let mut file = std::fs::File::create(&tmp)?;
        file.write_all(bytes)?;
        file.sync_all()
    })
    .context("writing the project's files")?;
    // The project file last, so that a project file is never newer than
    // what it names.
    let mut staged: Vec<PathBuf> = staged.into_iter().map(|(rel, _)| rel).collect();
    staged.sort_by_key(|rel| rel.as_os_str() == PROJECT_FILE);
    let mut touched_dirs = BTreeSet::new();
    for rel in &staged {
        let path = dir.join(rel);
        if rel.as_os_str() == PROJECT_FILE && path.is_file() {
            // The project file before is kept as `project.toml.bak`: a
            // damaged one is then put right from it (`:recover`).
            let bak = backup_of(dir);
            let _ = std::fs::remove_file(&bak);
            if std::fs::hard_link(&path, &bak).is_err() {
                let _ = std::fs::copy(&path, &bak);
            }
        }
        std::fs::rename(tmp_of(&path), &path)
            .with_context(|| format!("writing {}", path.display()))?;
        done.written.push(rel.clone());
        touched_dirs.extend(path.parent().map(Path::to_path_buf));
    }
    for (_, to) in &done.moved {
        touched_dirs.extend(dir.join(to).parent().map(Path::to_path_buf));
    }
    for rel in leaving.iter().filter(|r| !gone.contains(*r)) {
        let place = unused_place(dir, rel);
        if let Some(parent) = dir.join(&place).parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::rename(dir.join(rel), dir.join(&place))
            .with_context(|| format!("moving {} to {}", rel.display(), place.display()))?;
        done.unused.push(rel.clone());
        touched_dirs.extend(dir.join(&place).parent().map(Path::to_path_buf));
    }
    // Folders left empty by moves go; `rmdir` takes nothing that has a file.
    for rel in leaving.iter() {
        let mut parent = rel.parent();
        while let Some(p) = parent.filter(|p| !p.as_os_str().is_empty()) {
            if std::fs::remove_dir(dir.join(p)).is_err() {
                break;
            }
            parent = p.parent();
        }
    }
    if dir.join(".gitattributes").metadata().is_err() {
        std::fs::write(dir.join(".gitattributes"), GITATTRIBUTES)?;
        done.written.push(".gitattributes".into());
    }
    touched_dirs.insert(dir.to_path_buf());
    sync_dirs(&touched_dirs);
    Ok(done)
}

/// A project folder read back.
pub struct Read {
    pub project: Project,
    pub transport: Value,
    pub screen: Option<Value>,
    /// The file each MIDI clip's notes were read from, by clip id.
    pub clip_files: HashMap<u64, PathBuf>,
    /// What could not be read, said once each.
    pub problems: Vec<String>,
}

fn read_json(fs: &dyn ProjectFiles, path: &Path) -> Result<Value> {
    let text = fs.read(path).with_context(|| format!("reading {}", path.display()))?;
    serde_json::from_slice(&text).with_context(|| format!("parsing {}", path.display()))
}

/// The JSON of a part from its folder, its clips' files still to read:
/// (part, the files its MIDI clips name by the clips' place).
fn read_part(
    fs: &dyn ProjectFiles,
    home: &Home,
    dir: &Path,
    folder: &Path,
    problems: &mut Vec<String>,
) -> Result<Value> {
    let base = dir.join(folder);
    let mut part = read_json(fs, &base.join("part.json"))?;
    // A chain kept in a file outside the folder: the part refers to it.
    let chain_file = part
        .as_object_mut()
        .and_then(|t| t.remove("devices_file"))
        .and_then(|v| v.as_str().map(|s| home.resolve(Path::new(s), &base)));
    let (chain, chain_source) = match chain_file {
        Some(file) => match read_chain(fs, home, &file, problems) {
            Ok(chain) => (chain, Some(file)),
            Err(e) => {
                problems.push(format!("{e:#}: the part has no devices until it is there"));
                (Vec::new(), Some(file))
            }
        },
        None => (read_chain(fs, home, &base.join("devices.json"), problems)?, None),
    };
    let mut lanes = Vec::new();
    if let Some(Value::Array(list)) = part.get("lanes") {
        for name in list {
            let Some(name) = name.as_str() else { continue };
            lanes.push(read_json(fs, &home.resolve(Path::new(name), &base))?);
        }
    }
    let map = part.as_object_mut().context("a part")?;
    map.insert("devices".into(), Value::Array(chain));
    map.insert("lanes".into(), Value::Array(lanes));
    if let Some(file) = chain_source {
        map.insert("chain_source".into(), json!(file));
    }
    Ok(part)
}

/// The devices of a chain file (a `devices.json`), each with its state
/// read from the file beside it that it names. A file that is not there is
/// an empty chain.
pub(crate) fn read_chain(
    fs: &dyn ProjectFiles,
    home: &Home,
    file: &Path,
    problems: &mut Vec<String>,
) -> Result<Vec<Value>> {
    let base = file.parent().map(Path::to_path_buf).unwrap_or_default();
    let devices = match read_json(fs, file) {
        Ok(Value::Array(list)) => list,
        Ok(_) => bail!("{} is not a list of devices", file.display()),
        Err(e) if !fs.exists(file) => {
            let _ = e;
            Vec::new()
        }
        Err(e) => return Err(e),
    };
    let mut chain = Vec::new();
    for mut d in devices {
        if let Some(name) = d
            .get("state_file")
            .and_then(Value::as_str)
            .map(str::to_string)
        {
            let path = home.resolve(Path::new(&name), &base);
            match fs.read(&path) {
                Ok(bytes) => d["state"] = json!(BASE64.encode(bytes)),
                Err(e) => problems.push(format!("{}: {e}", path.display())),
            }
            d.as_object_mut().map(|o| o.remove("state_file"));
        }
        if let Some(names) = d.get("file_names").and_then(Value::as_object).cloned() {
            let mut files = serde_json::Map::new();
            for (key, name) in names {
                let Some(name) = name.as_str() else { continue };
                let path = home.resolve(Path::new(name), &base);
                match fs.read(&path) {
                    Ok(bytes) => {
                        files.insert(key, json!(BASE64.encode(bytes)));
                    }
                    Err(e) => problems.push(format!("{}: {e}", path.display())),
                }
            }
            d["files"] = Value::Object(files);
            d.as_object_mut().map(|o| o.remove("file_names"));
        }
        chain.push(d);
    }
    Ok(chain)
}

/// The folder that the clip files of a part folder outside the project are
/// named from: the project that the part folder is in (`<project>/parts/
/// <name>`), or the part folder itself.
fn part_root(folder: &Path) -> PathBuf {
    match folder.parent() {
        Some(parts) if parts.file_name().is_some_and(|n| n == "parts") => {
            parts.parent().map(Path::to_path_buf).unwrap_or_default()
        }
        _ => folder.to_path_buf(),
    }
}

/// The ids that a part's JSON gives to the part, its clips, devices and
/// lanes.
fn ids_in(part: &Value, used: &mut BTreeSet<u64>) {
    let id = |v: &Value| v.get("id").and_then(Value::as_u64);
    used.extend(id(part));
    // A chain from a file outside is numbered after the rest.
    let chain = if part.get("chain_source").is_some() { "" } else { "devices" };
    for key in ["clips", "cues", chain, "lanes"] {
        if let Some(Value::Array(list)) = part.get(key) {
            used.extend(list.iter().filter_map(id));
        }
    }
    if let Some(chain) = part
        .get("graph")
        .and_then(|g| serde_json::from_value::<Chain>(g.clone()).ok())
    {
        used.extend(chain.root.ids().into_iter().map(|id| id.get()));
    }
}

/// Give a new id to each thing of a part from outside (its devices alone
/// with `devices_only`) whose id a part of the project has, and take the
/// ids. A lane follows its device to its new id.
fn renumber(part: &mut Value, used: &mut BTreeSet<u64>, devices_only: bool) {
    let fresh = |v: &mut Value, used: &mut BTreeSet<u64>| -> Option<(u64, u64)> {
        let old = v.get("id").and_then(Value::as_u64)?;
        if used.insert(old) {
            return None;
        }
        let new = used.iter().next_back().map_or(1, |m| m + 1);
        used.insert(new);
        v["id"] = json!(new);
        Some((old, new))
    };
    let mut devices = HashMap::new();
    if let Some(Value::Array(list)) = part.get_mut("devices") {
        for d in list {
            devices.extend(fresh(d, used));
        }
    }
    if let Some(Value::Array(lanes)) = part.get_mut("lanes") {
        for lane in lanes {
            if let Some(target) = lane.get_mut("target")
                && let Some(new) = target.get("device").and_then(Value::as_u64).and_then(|d| devices.get(&d))
            {
                target["device"] = json!(new);
            }
            if !devices_only {
                fresh(lane, used);
            }
        }
    }
    // The chain follows its devices, and its own ids that the project has
    // get new ones.
    if let Some(value) = part.get_mut("graph")
        && let Ok(mut chain) = serde_json::from_value::<Chain>(value.clone())
    {
        let own: BTreeSet<u64> = chain
            .root
            .ids()
            .into_iter()
            .map(|id| id.get())
            .filter(|id| !devices.contains_key(id))
            .collect();
        let mut mapped: HashMap<u64, u64> = HashMap::new();
        for id in own {
            let new = if used.insert(id) {
                id
            } else {
                used.iter().next_back().map_or(1, |m| m + 1)
            };
            used.insert(new);
            mapped.insert(id, new);
        }
        chain.map_ids(&mut |id| {
            let id = id.get();
            devices
                .get(&id)
                .or_else(|| mapped.get(&id))
                .copied()
                .unwrap_or(id)
                .into()
        });
        *value = serde_json::to_value(&chain).unwrap_or(Value::Null);
    }
    if devices_only {
        return;
    }
    fresh(part, used);
    for key in ["clips", "cues"] {
        if let Some(Value::Array(clips)) = part.get_mut(key) {
            for clip in clips {
                fresh(clip, used);
            }
        }
    }
}

/// A part folder outside a project, read as a part that refers to it:
/// with ids the project does not have (`used`), and played into the
/// master with no sends, because the parts it played into are not here.
pub(crate) fn read_outside_part(
    fs: &dyn ProjectFiles,
    home: &Home,
    folder: &Path,
    used: &mut BTreeSet<u64>,
    problems: &mut Vec<String>,
) -> Result<Value> {
    let mut part = read_part(fs, home, Path::new(""), folder, problems)
        .with_context(|| format!("reading the part {}", folder.display()))?;
    renumber(&mut part, used, false);
    if let Some(map) = part.as_object_mut() {
        map.insert("source".into(), json!(folder));
        map.insert("output".into(), Value::Null);
        map.insert("sends".into(), json!([]));
        for key in ["origin", "chain_origin"] {
            map.remove(key);
        }
    }
    if let Some(Value::Array(devices)) = part.get_mut("devices") {
        for d in devices {
            if let Some(o) = d.as_object_mut() {
                o.remove("sidechain");
                o.remove("outputs");
            }
        }
    }
    Ok(part)
}

/// Whether a name in `project.toml`'s list of parts is a part folder
/// outside the project (a path), not a folder in its `parts`.
fn is_outside_entry(name: &str) -> bool {
    name.contains('/') || name.starts_with('~')
}

/// Take the file a clip's entry names out of it, leaving an empty note
/// list to fill.
fn take_clip_file(
    fs: &dyn ProjectFiles,
    home: &Home,
    clip: &mut Value,
    files: &mut Vec<(u64, PathBuf)>,
    dir: &Path,
) -> Result<()> {
    let id = clip.get("id").and_then(Value::as_u64).unwrap_or(0);
    let Some(content) = clip.get_mut("content") else {
        return Ok(());
    };
    if content.get("kind").and_then(Value::as_str) == Some("custom") {
        return take_custom_files(fs, home, content, dir);
    }
    if content.get("kind").and_then(Value::as_str) == Some("audio") {
        // An audio clip's edit list, from its file.
        if let Some(file) = content.as_object_mut().and_then(|c| c.remove("edits_file")) {
            let path = home.resolve(Path::new(file.as_str().unwrap_or_default()), dir);
            content["edits"] = read_json(fs, &path).unwrap_or_else(|_| json!([]));
        }
        return Ok(());
    }
    if content.get("kind").and_then(Value::as_str) != Some("midi") {
        return Ok(());
    }
    if let Some(file) = content.get("file").and_then(Value::as_str) {
        files.push((id, home.resolve(Path::new(file), dir)));
    }
    *content = json!({ "kind": "midi", "notes": [] });
    Ok(())
}

/// The text of a file that a custom clip's entry names.
fn read_text(fs: &dyn ProjectFiles, home: &Home, file: &str, dir: &Path) -> Result<String> {
    let path = home.resolve(Path::new(file), dir);
    let bytes = fs.read(&path).with_context(|| format!("reading {}", path.display()))?;
    String::from_utf8(bytes.into_owned()).with_context(|| format!("reading {}", path.display()))
}

/// Put the files that a custom clip's entry names back into it: its data,
/// its signals and its sound when that is MIDI. An error names the file and,
/// for JSON, the line and column.
fn take_custom_files(fs: &dyn ProjectFiles, home: &Home, content: &mut Value, dir: &Path) -> Result<()> {
    let Some(map) = content.as_object_mut() else {
        return Ok(());
    };
    let data = map.get("data").and_then(Value::as_object);
    if let Some(file) = data.and_then(|d| d.get("json_file")).and_then(Value::as_str) {
        let value = read_json(fs, &home.resolve(Path::new(file), dir))?;
        map.insert("data".into(), json!({ "json": value }));
    } else if let Some(file) = data.and_then(|d| d.get("text_file")).and_then(Value::as_str) {
        let ext = data.and_then(|d| d.get("ext")).cloned().unwrap_or(Value::Null);
        let text = read_text(fs, home, file, dir)?;
        map.insert("data".into(), json!({ "text": { "ext": ext, "text": text } }));
    }
    if let Some(file) = map.remove("signals_file") {
        let path = home.resolve(Path::new(file.as_str().unwrap_or_default()), dir);
        map.insert("signals".into(), read_json(fs, &path)?);
    }
    let sound = map.get("sound").and_then(|s| s.get("file")).and_then(Value::as_str);
    if let Some(file) = sound {
        let path = home.resolve(Path::new(file), dir);
        let bytes = fs.read(&path).with_context(|| format!("reading {}", path.display()))?;
        let read = clipfile::decode(&bytes).with_context(|| format!("reading {}", path.display()))?;
        let midi = ClipContent::Midi { notes: Notes::from(read.notes), controls: read.controls };
        map.insert("sound".into(), serde_json::to_value(&midi)?);
    }
    Ok(())
}

/// Read a project folder (`dir/project.toml`) from the disk.
pub(crate) fn read(home: &Home, dir: &Path) -> Result<Read> {
    read_from(&DiskFiles, home, dir)
}

/// Read the project folder `dir` from `fs`: the disk, or its files in
/// memory.
pub fn read_from(fs: &dyn ProjectFiles, home: &Home, dir: &Path) -> Result<Read> {
    read_with(fs, home, dir, &dir.join(PROJECT_FILE))
}

/// Read a project folder with `head_path` in place of its `project.toml`
/// (its `.bak`, for one that is damaged).
pub(crate) fn read_with(fs: &dyn ProjectFiles, home: &Home, dir: &Path, head_path: &Path) -> Result<Read> {
    read_at(fs, home, dir, head_path, 0)
}

/// [`read_with`] for a project folder that `depth` songs refer to as a
/// subproject (`nests::adopt_references`).
fn read_at(fs: &dyn ProjectFiles, home: &Home, dir: &Path, head_path: &Path, depth: usize) -> Result<Read> {
    let (mut head, order, nest_names, transport) = read_head(fs, head_path)?;
    let mut problems = Vec::new();
    let mut files = Vec::new();
    let mut entries: Vec<PartEntry> = order.iter().map(|name| PartEntry::of(name, Path::new(""), None)).collect();
    let mut references = Vec::new();
    let mut nests = nests::read_heads(fs, dir, &nest_names, &mut entries, &mut references)?;
    let (mut parts, master) = read_all_parts(fs, home, dir, &entries, &mut files, &mut problems)?;
    nests::tag_parts(&mut nests, &entries, &mut parts)?;
    let map = head
        .as_object_mut()
        .expect("read_head checked that the head is a table");
    map.insert("parts".into(), Value::Array(parts));
    if !nests.is_empty() {
        map.insert("nests".into(), Value::Array(nests));
    }
    map.insert("master".into(), master);
    let meta = match read_json(fs, &dir.join("meta.json")) {
        Ok(v) => v,
        Err(_) if !fs.exists(&dir.join("meta.json")) => json!({}),
        Err(e) => return Err(e),
    };
    map.insert("meta".into(), meta);
    if fs.exists(&dir.join("racks.json")) {
        map.insert("racks".into(), read_json(fs, &dir.join("racks.json"))?);
    }
    let screen = read_json(fs, &dir.join("screen.json")).ok();
    let mut project: Project =
        serde_json::from_value(head).with_context(|| format!("reading {}", dir.display()))?;
    let clip_files = fill_clips(fs, &mut project, &files, &mut problems, dir);
    old_meta::convert(&mut project);
    nests::adopt_references(fs, home, dir, &mut project, references, &mut problems, depth)?;
    Ok(Read {
        project,
        transport,
        screen,
        clip_files,
        problems,
    })
}

/// The head of a project folder (`project.toml`): the head as JSON
/// without the lists of parts and nests and the transport, which come
/// back apart.
fn read_head(fs: &dyn ProjectFiles, head_path: &Path) -> Result<(Value, Vec<String>, Vec<String>, Value)> {
    let bytes = fs.read(head_path).with_context(|| format!("reading {}", head_path.display()))?;
    let text = std::str::from_utf8(&bytes).with_context(|| format!("reading {}", head_path.display()))?;
    let head: toml::Value =
        toml::from_str(text).with_context(|| format!("parsing {}", head_path.display()))?;
    let mut head = from_toml(head);
    let map = head
        .as_object_mut()
        .context("project.toml is not a table")?;
    let version = map
        .remove("version")
        .and_then(|v| v.as_u64())
        .unwrap_or(VERSION as u64);
    if version > VERSION as u64 {
        bail!("{} was saved by a newer version", head_path.display());
    }
    let order: Vec<String> = match map.remove("parts") {
        Some(v) => {
            serde_json::from_value(v).context("project.toml: parts is a list of folder names")?
        }
        None => Vec::new(),
    };
    let nests: Vec<String> = match map.remove("nests") {
        Some(v) => {
            serde_json::from_value(v).context("project.toml: nests is a list of folder names")?
        }
        None => Vec::new(),
    };
    let transport = map.remove("transport").unwrap_or(Value::Null);
    Ok((head, order, nests, transport))
}

/// A part to read: from its folder in the project, or from a part folder
/// outside it, for the song or a nest.
struct PartEntry {
    /// The folder in the project (`parts/Bass`, `nests/Bridge/master`), or
    /// the path of one outside it as the list names it.
    folder: PathBuf,
    outside: bool,
    nest: Option<u64>,
    /// The nest's master part (`nests/<name>/master`).
    master: bool,
}

impl PartEntry {
    /// An entry of a list of parts (`project.toml`'s, a `nest.toml`'s)
    /// whose folders are in `<root>/parts`.
    fn of(name: &str, root: &Path, nest: Option<u64>) -> Self {
        if is_outside_entry(name) {
            Self { folder: PathBuf::from(name), outside: true, nest, master: false }
        } else {
            Self { folder: root.join("parts").join(name), outside: false, nest, master: false }
        }
    }
}

/// Read every part and the master, outside parts included. The clips'
/// files that the parts name are collected in `files`.
fn read_all_parts(
    fs: &dyn ProjectFiles,
    home: &Home,
    dir: &Path,
    entries: &[PartEntry],
    files: &mut Vec<(u64, PathBuf)>,
    problems: &mut Vec<String>,
) -> Result<(Vec<Value>, Value)> {
    let mut parts = Vec::new();
    let fix = |mut part: Value, files: &mut Vec<(u64, PathBuf)>, root: &Path| -> Result<Value> {
        for key in ["clips", "cues"] {
            if let Some(Value::Array(clips)) = part.get_mut(key) {
                for clip in clips {
                    take_clip_file(fs, home, clip, files, root)?;
                }
            }
        }
        Ok(part)
    };
    // The project's own parts first: their ids are the project's. What
    // comes from outside (a part folder, a chain file) keeps its ids where
    // no part of the project has them, and gets new ones where one has.
    let mut read_parts: Vec<Option<Value>> = Vec::new();
    let mut used = BTreeSet::new();
    for entry in entries {
        if entry.outside {
            read_parts.push(None);
            continue;
        }
        let part = read_part(fs, home, dir, &entry.folder, problems)
            .with_context(|| format!("reading the part {}", entry.folder.display()))?;
        ids_in(&part, &mut used);
        read_parts.push(Some(part));
    }
    let mut master = if fs.exists(&dir.join("master/part.json")) {
        read_part(fs, home, dir, Path::new("master"), problems)?
    } else {
        serde_json::to_value(&*Project::default().master)?
    };
    ids_in(&master, &mut used);
    for part in read_parts.iter_mut().flatten().chain(std::iter::once(&mut master)) {
        if part.get("chain_source").is_some() {
            renumber(part, &mut used, true);
        }
    }
    for (entry, part) in entries.iter().zip(read_parts) {
        if let Some(part) = part {
            parts.push(fix(part, files, dir)?);
            continue;
        }
        // A part folder outside the project: read from where it is.
        let folder = home.resolve(&entry.folder, dir);
        let part = read_outside_part(fs, home, &folder, &mut used, problems)?;
        parts.push(fix(part, files, &part_root(&folder))?);
    }
    let master = fix(master, files, dir)?;
    Ok((parts, master))
}

/// Give the clips of the project their notes from the clips' files, each
/// file read once however many clips share it. Returns each clip's file.
fn fill_clips(
    fs: &dyn ProjectFiles,
    project: &mut Project,
    files: &[(u64, PathBuf)],
    problems: &mut Vec<String>,
    dir: &Path,
) -> HashMap<u64, PathBuf> {
    // The clips' files, each once however many clips share it, on as many
    // threads as there are cores.
    let unique: Vec<PathBuf> = files
        .iter()
        .map(|(_, p)| p.clone())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    let decoded = read_clips(fs, &unique);
    left_out(&unique, &decoded, problems);
    // The notes of each file made once: the clips that name one file (the
    // clips of a link, a split clip's halves) share them, as copies do.
    type FileNotes<'r> = (Notes, &'r [Control]);
    type Decoded<'r> = Result<FileNotes<'r>, &'r anyhow::Error>;
    let decoded: Vec<Decoded<'_>> = decoded
        .iter()
        .map(|read| read.as_ref().map(|clip| (Notes::from(clip.notes.clone()), clip.controls.as_slice())))
        .collect();
    let mut by_path: HashMap<&Path, &Decoded<'_>> = HashMap::new();
    for (path, clip) in unique.iter().zip(&decoded) {
        by_path.insert(path, clip);
    }
    let mut clip_files = HashMap::new();
    let mut contents: HashMap<u64, (Option<&FileNotes<'_>>, PathBuf)> = HashMap::new();
    for (id, path) in files {
        clip_files.insert(*id, path.clone());
        let read = match by_path.get(path.as_path()) {
            Some(Ok(clip)) => Some(clip),
            Some(Err(e)) => {
                problems.push(format!("{e:#}: the clip stays empty until it is there"));
                None
            }
            None => None,
        };
        contents.insert(*id, (read, path.clone()));
    }
    let tidy_dir = tidy(dir);
    let fill = |clip: &mut Arc<Clip>| {
        let Some((read, path)) = contents.get(&clip.id) else {
            return;
        };
        let clip = Arc::make_mut(clip);
        if let Some((read_notes, read_controls)) = read
            && let ClipContent::Midi { notes, controls } = &mut clip.content
        {
            *notes = read_notes.clone();
            *controls = read_controls.to_vec();
        }
        // A file outside the folder, or one that is missing, stays where
        // the project said it is.
        if !path.starts_with(&tidy_dir) || read.is_none() {
            clip.source = Some(path.clone());
        }
    };
    for part in project
        .parts
        .iter_mut()
        .chain(std::iter::once(&mut project.master))
    {
        let needs = part
            .clips
            .iter()
            .chain(&part.cues)
            .any(|c| contents.contains_key(&c.id));
        if !needs {
            continue;
        }
        let part = Arc::make_mut(part);
        for clip in &mut part.clips {
            fill(clip);
        }
        for clip in &mut part.cues {
            fill(clip);
        }
    }
    clip_files
}

/// Say what each clip file read had that its clip has no place for, such
/// as a lyric with no note: an open tells it, as an import does.
fn left_out(paths: &[PathBuf], read: &[Result<clipfile::Clip>], problems: &mut Vec<String>) {
    for (path, clip) in paths.iter().zip(read) {
        if let Ok(clip) = clip
            && !clip.skipped.is_empty()
        {
            problems.push(format!("{}: left out {}", path.display(), clip.skipped.join(", ")));
        }
    }
}

/// Read and decode clip files, in parallel.
fn read_clips(fs: &dyn ProjectFiles, paths: &[PathBuf]) -> Vec<Result<clipfile::Clip>> {
    let one = |path: &PathBuf| -> Result<clipfile::Clip> {
        let bytes = fs.read(path).with_context(|| format!("reading {}", path.display()))?;
        clipfile::decode(&bytes)
    };
    let threads = std::thread::available_parallelism()
        .map_or(1, |n| n.get())
        .min(8);
    if paths.len() < 64 || threads < 2 {
        return paths.iter().map(one).collect();
    }
    let chunk = paths.len().div_ceil(threads);
    std::thread::scope(|s| {
        let handles: Vec<_> = paths
            .chunks(chunk)
            .map(|chunk| s.spawn(move || chunk.iter().map(one).collect::<Vec<_>>()))
            .collect();
        handles
            .into_iter()
            .flat_map(|h| h.join().unwrap_or_default())
            .collect()
    })
}

impl super::Session {
    /// The project's folder and its files as a save would write them now,
    /// or `None` for a project that is not kept in a folder.
    fn folder_layout(&mut self) -> Result<Option<(PathBuf, Layout)>> {
        let Some(file) = self.path.clone() else {
            return Ok(None);
        };
        if file.file_name().is_none_or(|n| n != PROJECT_FILE) {
            return Ok(None);
        }
        let dir = file.parent().map(Path::to_path_buf).unwrap_or_default();
        self.capture_states();
        let project = self.file_project(&file);
        let transport = serde_json::to_value(&self.transport)?;
        let mut layout = layout(&project, &transport, self.screen.as_ref(), &dir, &self.home)?;
        self.add_media_file(&mut layout, &dir);
        Ok(Some((dir, layout)))
    }

    /// Put `media.json` into the files of the folder `dir`, when the project
    /// uses any file.
    fn add_media_file(&mut self, layout: &mut Layout, dir: &Path) {
        let media = self.media_for_folder(dir);
        if !media.is_empty() {
            layout.files.insert(MEDIA_FILE.into(), media.to_json());
        }
    }

    /// The files of a project kept in a folder, each with what it holds and
    /// whether it differs from the file on the disk: `{ path, modified,
    /// what, part, clip }`. Empty for a project in one file or none.
    pub(crate) fn project_files(&mut self) -> Result<Value> {
        let Some((dir, layout)) = self.folder_layout()? else {
            return Ok(json!([]));
        };
        let mut owner: HashMap<&Path, (u64, Option<u64>)> = HashMap::new();
        for (part, folder) in &layout.part_folders {
            owner.insert(folder.as_path(), (*part, None));
        }
        let clip_of: HashMap<&Path, u64> = layout
            .clip_files
            .iter()
            .map(|(id, p)| (p.as_path(), *id))
            .collect();
        let mut out = Vec::new();
        for (rel, bytes) in &layout.files {
            let modified = std::fs::read(dir.join(rel)).map_or(true, |old| &old != bytes);
            let part = rel.ancestors().find_map(|a| owner.get(a).map(|o| o.0));
            let what = match rel.extension().and_then(|e| e.to_str()) {
                Some("midi2") => "clip",
                Some("state") => "state",
                _ if rel.file_name().is_some_and(|n| n == nests::NEST_FILE) => "nest",
                Some("toml") => "project",
                _ if rel.to_string_lossy().ends_with(".edits.json") => "edits",
                _ if rel.to_string_lossy().ends_with(".signals.json") => "signals",
                _ if rel.parent().and_then(Path::file_name).is_some_and(|n| n == "clips") => "data",
                _ if ["parts", "master", "nests", "unused"].iter().any(|d| rel.starts_with(d))
                    && rel.file_name().is_some_and(|n| n != "meta.json") =>
                {
                    match rel.file_name().and_then(|n| n.to_str()) {
                        Some("part.json") => "part",
                        Some("devices.json") => "devices",
                        _ => "automation",
                    }
                }
                _ => match rel.file_name().and_then(|n| n.to_str()) {
                    Some("screen.json") => "screen",
                    Some(MEDIA_FILE) => "media",
                    _ => "meta",
                },
            };
            out.push(json!({
                "path": rel,
                "modified": modified,
                "what": what,
                "part": part,
                "clip": clip_of.get(rel.as_path()),
            }));
        }
        Ok(Value::Array(out))
    }

    /// Save some of the files of a project kept in a folder, by their path
    /// in it. The project counts as saved when no file differs any more.
    /// Returns the paths written.
    pub(crate) fn project_save_files(&mut self, paths: &[PathBuf]) -> Result<Vec<PathBuf>> {
        let Some(file) = self
            .path
            .clone()
            .filter(|f| f.file_name().is_some_and(|n| n == PROJECT_FILE))
        else {
            bail!("the project is not kept in a folder: `:w` saves all of it");
        };
        let mut only: BTreeSet<PathBuf> = paths.iter().cloned().collect();
        // A file written names others: those not on the disk yet go too,
        // so that everything the written files name is there.
        if let Some((dir, layout)) = self.folder_layout()? {
            loop {
                let more: Vec<PathBuf> = layout
                    .files
                    .keys()
                    .filter(|rel| !only.contains(*rel) && !dir.join(rel).exists())
                    .filter(|rel| {
                        only.iter().any(|o| {
                            o.as_os_str() == PROJECT_FILE
                                || (o.file_name().is_some_and(|n| n == "part.json")
                                    && o.parent().is_some_and(|f| rel.starts_with(f)))
                        })
                    })
                    .cloned()
                    .collect();
                if more.is_empty() {
                    break;
                }
                only.extend(more);
            }
        }
        let (_, done) = self.project_save_folder(&file, Some(&only))?;
        if let Some((dir, layout)) = self.folder_layout()?
            && layout
                .files
                .iter()
                .all(|(rel, bytes)| std::fs::read(dir.join(rel)).is_ok_and(|old| &old == bytes))
        {
            self.doc.undo.history.mark_saved(false);
        }
        Ok(done.written)
    }

    /// Open the project kept in a folder: `song`, or `song/project.toml`.
    pub(super) fn project_load_folder(&mut self, path: &Path) -> Result<()> {
        let file = std::path::absolute(project_file(path))?;
        let dir = file.parent().map(Path::to_path_buf).unwrap_or_default();
        let read = read(&self.home, &dir)?;
        let mut project = read.project;
        project
            .validate()
            .with_context(|| format!("{} cannot be loaded", dir.display()))?;
        let transport: super::Transport = if read.transport.is_null() {
            super::Transport::default()
        } else {
            serde_json::from_value(read.transport).context("project.toml: transport")?
        };
        let moved = self.find_media(&mut project, &file);
        self.replace_project(project, transport, Some(file));
        self.screen = read.screen;
        for problem in read.problems {
            self.doc.warnings.push(problem);
        }
        self.doc.undo.touched |= moved;
        Ok(())
    }

    /// Read the project kept in a folder (`song`, or `song/project.toml`)
    /// without opening it, to compare it with the project that is open.
    /// `files` gives the folder's own files by their path in it, for a
    /// version that is not on the disk (a revision of git). Without
    /// `files`, the reader takes them from the disk. The other files (the
    /// media, and the part folders outside the project) always come from
    /// the disk.
    pub(crate) fn project_read(
        &self,
        path: &Path,
        files: Option<BTreeMap<PathBuf, Arc<[u8]>>>,
    ) -> Result<Project> {
        let file = std::path::absolute(project_file(path))?;
        let dir = file.parent().map(Path::to_path_buf).unwrap_or_default();
        let read = match files {
            Some(files) => read_from(&MemoryFiles::new(&dir, files), &self.home, &dir)?,
            None => read(&self.home, &dir)?,
        };
        Ok(read.project)
    }

    /// Every id the project gives out now, and the next one it will, so that
    /// parts from outside get ids of their own.
    fn used_ids(&self) -> BTreeSet<u64> {
        let mut used = BTreeSet::new();
        for t in self.doc.project.all_parts() {
            used.insert(t.id);
            used.extend(t.clips.iter().map(|c| c.id));
            used.extend(t.cues.iter().map(|c| c.id));
            used.extend(t.devices.iter().map(|d| d.id));
            used.extend(t.lanes.iter().map(|l| l.id));
        }
        used.insert(self.doc.next_id);
        used
    }

    /// Add the part of a part folder outside the project (one with a
    /// `part.json`), at `index` (from 1; the end when `None`). The project
    /// refers to the folder and keeps no copy, until the part's first edit.
    /// Returns the part's id.
    pub(crate) fn part_import_folder(&mut self, folder: &Path, index: Option<usize>) -> Result<u64> {
        let folder = tidy(&std::path::absolute(folder)?);
        if !folder.join("part.json").is_file() {
            bail!("{} is not a part folder: it has no part.json", folder.display());
        }
        let mut used = self.used_ids();
        let mut problems = Vec::new();
        let mut value = read_outside_part(&DiskFiles, &self.home, &folder, &mut used, &mut problems)?;
        let root = part_root(&folder);
        let mut files = Vec::new();
        for key in ["clips", "cues"] {
            if let Some(Value::Array(clips)) = value.get_mut(key) {
                for clip in clips {
                    take_clip_file(&DiskFiles, &self.home, clip, &mut files, &root)?;
                }
            }
        }
        let mut part: Part = serde_json::from_value(value).with_context(|| format!("reading {}", folder.display()))?;
        let unique: Vec<PathBuf> = files.iter().map(|(_, p)| p.clone()).collect::<BTreeSet<_>>().into_iter().collect();
        let read = read_clips(&DiskFiles, &unique);
        left_out(&unique, &read, &mut problems);
        let decoded: HashMap<PathBuf, Result<clipfile::Clip>> = unique.iter().cloned().zip(read).collect();
        let by_id: HashMap<u64, PathBuf> = files.into_iter().collect();
        for clip in part.clips.iter_mut().chain(part.cues.iter_mut()) {
            let Some(path) = by_id.get(&clip.id) else {
                continue;
            };
            let clip = Arc::make_mut(clip);
            match decoded.get(path) {
                Some(Ok(read)) => {
                    if let ClipContent::Midi { notes, controls } = &mut clip.content {
                        *notes = Notes::from(read.notes.clone());
                        *controls = read.controls.clone();
                    }
                }
                Some(Err(e)) => problems.push(format!("{e:#}: the clip stays empty until it is there")),
                None => {}
            }
            clip.source = Some(path.clone());
        }
        let id = part.id;
        self.doc.edit(|p| {
            let at = index.map_or(usize::MAX, |i| i.saturating_sub(1)).min(p.parts.len());
            p.parts.insert(at, Arc::new(part));
            Ok(())
        })?;
        self.doc.next_id = self.doc.next_id.max(self.doc.project.max_id() + 1);
        self.doc.warnings.extend(problems);
        self.watch_project_files();
        Ok(id)
    }

    /// Give a part the chain of devices in a chain file (a `devices.json`
    /// and the `.state` files beside it). With `refer`, the part refers to
    /// the file and keeps no copy until the chain's first edit; without, the
    /// devices are the part's own at once. Returns how many devices.
    pub(crate) fn part_chain_file(&mut self, part: u64, file: &Path, refer: bool) -> Result<usize> {
        let file = tidy(&std::path::absolute(file)?);
        if !file.is_file() {
            bail!("{}: no such chain file", file.display());
        }
        let mut problems = Vec::new();
        let chain = read_chain(&DiskFiles, &self.home, &file, &mut problems)?;
        let mut used = self.used_ids();
        let mut value = json!({ "devices": chain });
        renumber(&mut value, &mut used, true);
        let devices: Vec<Arc<crate::model::DeviceInst>> =
            serde_json::from_value(value["devices"].take()).with_context(|| format!("reading {}", file.display()))?;
        let count = devices.len();
        self.doc.edit(|p| {
            let t = p.part_mut(part).with_context(|| format!("no part {part}"))?;
            t.devices = devices;
            // Lanes of the devices that went go with them.
            let ids: BTreeSet<u64> = t.devices.iter().map(|d| d.id).collect();
            t.lanes.retain(|l| l.target.device().is_none_or(|d| ids.contains(&d)));
            t.chain_source = refer.then(|| file.clone());
            t.chain_origin = None;
            Ok(())
        })?;
        self.doc.next_id = self.doc.next_id.max(self.doc.project.max_id() + 1);
        self.doc.warnings.extend(problems);
        self.watch_project_files();
        Ok(count)
    }

    /// Write a part's chain of devices as a chain file: `file` (a
    /// `devices.json`) and a `.state` file beside it for each plugin's state.
    /// Returns the files written.
    pub(crate) fn chain_write(&mut self, part: u64, file: &Path) -> Result<Vec<PathBuf>> {
        self.capture_states();
        let mut t = self.doc.project.part(part).with_context(|| format!("no part {part}"))?.clone();
        self.keep_param_ids(&mut t);
        let dir = file.parent().map(Path::to_path_buf).unwrap_or_default();
        let (devices, states) = chain_files(&t)?;
        let mut written = Vec::new();
        for (name, bytes) in states {
            let path = dir.join(name);
            crate::safe::write_file(&path, &bytes, false)?;
            written.push(path);
        }
        crate::safe::write_file(file, &pretty(&Value::Array(devices)), false)?;
        written.push(file.to_path_buf());
        Ok(written)
    }

    /// Open a project folder whose `project.toml` is damaged from its
    /// `project.toml.bak` (`bak`) and the rest of its files, as changed
    /// since it was saved, so that `:w` puts its project file right.
    pub(super) fn project_recover_folder(&mut self, bak: &Path) -> Result<Value> {
        let bak = std::path::absolute(bak)?;
        let dir = bak.parent().map(Path::to_path_buf).unwrap_or_default();
        let file = dir.join(PROJECT_FILE);
        let read = read_with(&DiskFiles, &self.home, &dir, &bak)?;
        let mut project = read.project;
        project
            .validate()
            .with_context(|| format!("{} cannot be recovered", bak.display()))?;
        let transport: super::Transport = if read.transport.is_null() {
            super::Transport::default()
        } else {
            serde_json::from_value(read.transport).unwrap_or_default()
        };
        self.find_media(&mut project, &file);
        self.replace_project(project, transport, Some(file));
        self.screen = read.screen;
        for problem in read.problems {
            self.doc.warnings.push(problem);
        }
        // It differs from what is on disk: the project file is damaged.
        self.doc.undo.touched = true;
        self.doc.undo.edits += 1;
        Ok(Value::Null)
    }

    /// Save the project as a folder, at `path` (the folder or its
    /// `project.toml`). With `only`, only those of its files (by their path
    /// in the folder), and the project does not count as saved.
    pub(crate) fn project_save_folder(
        &mut self,
        path: &Path,
        only: Option<&BTreeSet<PathBuf>>,
    ) -> Result<(PathBuf, Committed)> {
        let file = std::path::absolute(project_file(path))?;
        let dir = file.parent().map(Path::to_path_buf).unwrap_or_default();
        if only.is_none() {
            self.adopt_recordings(&file)?;
        }
        self.capture_states();
        // What is saved is everything up to here and nothing after.
        self.checkpoint();
        // A project that was never named takes its folder's name.
        let named = (self.doc.project.name == Project::default().name)
            .then(|| dir.file_name().map(|s| s.to_string_lossy().into_owned()))
            .flatten()
            .filter(|name| !name.is_empty());
        let mut project = self.file_project(&file);
        if let Some(name) = &named {
            project.name = name.clone();
        }
        let transport = serde_json::to_value(&self.transport)?;
        let mut layout = layout(&project, &transport, self.screen.as_ref(), &dir, &self.home)?;
        self.add_media_file(&mut layout, &dir);
        let done = commit(&dir, &layout, only)?;
        // Its own writes are not changes made outside paw.
        self.files_there.forget();
        for rel in &done.written {
            let bytes = layout.files.get(rel).map(Vec::as_slice);
            self.files_watch.wrote(dir.join(rel), bytes);
        }
        for (from, to) in &done.moved {
            self.files_watch.wrote(dir.join(from), None);
            let bytes = layout.files.get(to).map(Vec::as_slice);
            self.files_watch.wrote(dir.join(to), bytes);
        }
        for rel in &done.unused {
            self.files_watch.wrote(dir.join(rel), None);
        }
        let renamed = self.path.as_ref() != Some(&file);
        self.path = Some(file.clone());
        if let Some(name) = named {
            // Not an edit to undo: the saved state is the named one.
            self.doc.project.name = name.clone();
            self.doc.undo.checkpoint.name = name;
            self.doc.undo.history.set_current_snapshot(self.doc.undo.checkpoint.clone());
            self.doc.dirty = true;
        }
        if only.is_none() {
            self.doc.undo.history.mark_saved(false);
        }
        self.remember_for_panic();
        if renamed || !done.written.is_empty() || !done.moved.is_empty() {
            // New folders, or a new place: watch them.
            let changed = std::mem::take(&mut self.files_watch.changed);
            self.watch_project_files();
            self.files_watch.changed = changed;
        }
        if only.is_none() {
            // The undo file keeps these files as the state saved.
            self.undo_file.saved_files = Some((self.doc.undo.history.current(), layout.files));
        }
        let saved = Saved {
            path: file.clone(),
            written: Some(done.written.clone()),
            unused: Some(done.unused.clone()),
            moved: Some(done.moved.clone()),
        };
        self.doc.emit(E::ProjectSaved(saved));
        Ok((file, done))
    }
}

#[cfg(test)]
#[expect(clippy::disallowed_methods, reason = "a measure of work in a test that prints times and asserts none")]
mod tests {
    use super::*;
    use crate::model::{Clip, ClipContent, Note, Project, Part};

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "paw-folder-{name}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    fn clip(id: u64, name: &str, start: f64, seed: u64) -> Arc<Clip> {
        let notes: Vec<Note> = (0..12)
            .map(|i| Note {
                start: i as f64 / 3.0,
                length: 0.25,
                pitch: 48 + ((i * 7 + seed) % 24) as u8,
                velocity: crate::model::Velocity(64 + ((i * 13 + seed) % 63) as u8),
                meta: Map::new(),
                lyric: None,
                id: i + 1,
                attr: None,
            })
            .collect();
        let value = json!({
            "id": id, "name": name, "start": start, "length": 4.0, "muted": false,
            "content": { "kind": "midi", "notes": [] },
        });
        let mut clip: Clip = serde_json::from_value(value).unwrap();
        clip.content = ClipContent::Midi {
            notes: Notes::from(notes),
            controls: Vec::new(),
        };
        Arc::new(clip)
    }

    fn project(parts: u64, clips: u64) -> Project {
        let mut p = Project::default();
        let mut id = 1;
        for t in 0..parts {
            let mut part = Part::new(id);
            id += 1;
            part.name = format!("T{t}");
            for c in 0..clips {
                part
                    .clips
                    .push(clip(id, &format!("c{c}"), c as f64 * 4.0, t * 31 + c));
                id += 1;
            }
            p.parts.push(Arc::new(part));
        }
        p
    }

    fn notes_of(p: &Project) -> Vec<Vec<Note>> {
        p.all_parts()
            .flat_map(|t| &t.clips)
            .map(|c| match &c.content {
                ClipContent::Midi { notes, .. } => notes.to_vec(),
                _ => Vec::new(),
            })
            .collect()
    }

    fn custom(id: u64, name: &str, start: f64, content: Value) -> Arc<Clip> {
        let value = json!({
            "id": id, "name": name, "start": start, "length": 4.0, "muted": false,
            "content": content,
        });
        Arc::new(serde_json::from_value(value).unwrap())
    }

    #[test]
    fn a_change_of_one_modifier_value_is_one_changed_line_of_part_json() {
        let dir = scratch("modifiers");
        let part_json = |velocity: i64| {
            let mut p = project(1, 1);
            let part = Arc::make_mut(&mut p.parts[0]);
            let clip = Arc::make_mut(&mut part.clips[0]);
            clip.stack = serde_json::from_value(json!([
                { "kind": "transpose", "params": { "semitones": 3 } },
                { "kind": "velocity", "params": { "add": velocity }, "off": true },
            ]))
            .unwrap();
            let files = layout(&p, &json!({}), None, &dir, &Home::default()).unwrap().files;
            let text = files.into_iter().find(|(f, _)| f.ends_with("T0/part.json")).unwrap().1;
            String::from_utf8(text).unwrap()
        };
        let (before, after) = (part_json(-10), part_json(-20));
        assert!(
            before.contains("\"modifiers\": [\n") && !before.contains("overrides"),
            "{before}"
        );
        let changed: Vec<_> = before.lines().zip(after.lines()).filter(|(a, b)| a != b).collect();
        assert_eq!(before.lines().count(), after.lines().count());
        assert_eq!(changed, [("            \"add\": -10", "            \"add\": -20")]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn custom_clips_save_their_data_in_one_canonical_form() {
        let dir = scratch("custom");
        let data = json!({ "zeta": 1.5, "alpha": [3, 2], "cue": { "text": "one" } });
        let signals = json!([
            { "at": 1.0, "to": { "kind": "kernel", "body": { "b": 1000.0, "a": 0 } } },
            { "at": 2.0, "to": { "kind": "osc", "port": "qlc", "address": "/go", "args": [1, 0.5, "x"] } },
        ]);
        let video = json!({
            "kind": "custom", "type": "video", "data": { "json": data }, "signals": signals,
            "media": [
                { "role": "source", "path": "media/film.mp4" },
                { "role": "proxy", "path": "media/derived/video-3f9a.flac", "derived": true },
            ],
            "sound": { "kind": "midi", "notes": [
                { "start": 0.5, "length": 1.0, "pitch": 60, "velocity": 90, "id": 1 }] },
        });
        let lyrics = json!({
            "kind": "custom", "type": "lyrics", "version": 2, "timeline": "seconds",
            "data": { "text": { "ext": "lrc", "text": "[00:01.00]one\n[00:02.00]two" } },
        });
        let mut part = Part::new(1);
        part.name = "Show".into();
        part.clips = vec![
            custom(2, "intro", 0.0, video.clone()),
            // A split keeps the data: both halves name one data file.
            custom(3, "intro", 4.0, video),
            custom(4, "verse", 8.0, lyrics),
        ]
        .into();
        let mut p = Project::default();
        p.parts.push(Arc::new(part));
        let first = layout(&p, &json!({}), None, &dir, &Home::default()).unwrap();
        let clips = Path::new("parts/Show/clips");
        let names: Vec<_> = first
            .files
            .keys()
            .filter_map(|f| f.strip_prefix(clips).ok())
            .map(|f| f.to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            names,
            ["intro.signals.json", "intro.sound.midi2", "intro.video.json", "verse.lyrics.lrc"]
        );
        // Pretty, with the keys sorted: one field is one line.
        let text = String::from_utf8(first.files[&clips.join("intro.video.json")].clone()).unwrap();
        assert_eq!(
            text,
            "{\n  \"alpha\": [\n    3,\n    2\n  ],\n  \"cue\": {\n    \"text\": \"one\"\n  },\n  \"zeta\": 1.5\n}\n"
        );
        let saved: Value = serde_json::from_slice(&first.files[&clips.join("intro.signals.json")]).unwrap();
        assert_eq!(saved[0]["to"]["body"], json!({ "a": 0, "b": 1000.0 }), "a body is JSON, not a string");
        assert_eq!(first.files[&clips.join("verse.lyrics.lrc")], b"[00:01.00]one\n[00:02.00]two");
        assert_eq!(first.clip_files[&2], first.clip_files[&3], "the halves share a data file");
        commit(&dir, &first, None).unwrap();
        // Read it back, with no kind defined anywhere: the same value, and
        // saved again as the same bytes.
        let read = read(&Home::default(), &dir).unwrap();
        assert!(read.problems.is_empty(), "{:?}", read.problems);
        let ClipContent::Custom(video) = &read.project.parts[0].clips[0].content else {
            panic!("a custom clip");
        };
        assert_eq!(video.data, KindData::Json(data.into()));
        let again = super::layout(&read.project, &json!({}), None, &dir, &Home::default()).unwrap();
        assert_eq!(again.files, first.files);
        let ClipContent::Custom(c) = &read.project.parts[0].clips[2].content else {
            panic!("a custom clip");
        };
        assert_eq!((c.version.get(), c.timeline), (2, crate::model::Timeline::Seconds));
        assert!(commit(&dir, &again, None).unwrap().written.is_empty());
        // A data file that is not JSON is said with its name and the place.
        std::fs::write(dir.join(clips).join("intro.video.json"), "{\n  \"a\": }").unwrap();
        let err = format!("{:#}", read_err(&dir));
        assert!(err.contains("intro.video.json") && err.contains("line 2 column 8"), "{err}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn read_err(dir: &Path) -> anyhow::Error {
        read(&Home::default(), dir).err().expect("the data file is not JSON")
    }

    /// The demo song of tests/fixtures.
    fn demo() -> Project {
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/demo-song.json");
        let file: Value = serde_json::from_slice(&std::fs::read(fixture).unwrap()).unwrap();
        serde_json::from_value(file["project"].clone()).unwrap()
    }

    #[test]
    fn a_project_folder_has_the_files_of_the_golden_file() {
        // Two parts of the demo song: a synth with a clip, a lane of
        // automation and a send, and the effect part that the send feeds.
        let mut song = demo();
        song.parts.retain(|t| matches!(t.name.as_str(), "Lead" | "Reverb"));
        song.meta.insert("composer".into(), json!("paw"));
        let transport = serde_json::to_value(crate::session::Transport::default()).unwrap();
        let screen = json!({ "tabs": [{ "view": "arrange" }] });
        let dir = tempfile::tempdir().unwrap();
        let layout = layout(&song, &transport, Some(&screen), dir.path(), &Home::default()).unwrap();
        commit(dir.path(), &layout, None).unwrap();
        crate::golden::settings(dir.path()).bind(|| {
            insta::assert_snapshot!(crate::golden::folder_text(dir.path()));
        });
    }

    #[test]
    fn a_project_comes_back_from_its_folder() {
        let dir = scratch("round");
        let p = project(3, 4);
        let layout = layout(&p, &json!({}), None, &dir, &Home::default()).unwrap();
        commit(&dir, &layout, None).unwrap();
        let read = read(&Home::default(), &dir).unwrap();
        assert_eq!(read.project.parts.len(), 3);
        let mut named = read.project.clone();
        named.name_notes(&Project::default());
        assert!(notes_of(&named) == notes_of(&p), "the notes differ");
        // The same project, the same bytes, and nothing written again.
        let again = super::layout(&read.project, &json!({}), None, &dir, &Home::default()).unwrap();
        assert_eq!(again.files, layout.files);
        let done = commit(&dir, &again, None).unwrap();
        assert!(done.written.is_empty(), "{:?}", done.written);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A project with a part kind, a group of three levels and a sung note,
    /// written and read in memory.
    fn kinds_round_trip(p: &Project) -> (Project, BTreeMap<PathBuf, Vec<u8>>) {
        use crate::session::project_files::MemoryFiles;
        let dir = scratch("kinds");
        let layout = layout(p, &json!({}), None, &dir, &Home::default()).unwrap();
        let files: BTreeMap<_, _> = layout.files.into_iter().collect();
        let memory = files.iter().map(|(k, v)| (k.clone(), Arc::from(v.as_slice()))).collect();
        let read = read_from(&MemoryFiles::new(&dir, memory), &Home::default(), &dir).unwrap();
        assert!(read.problems.is_empty(), "{:?}", read.problems);
        (read.project, files)
    }

    #[test]
    fn a_part_kind_a_group_tree_and_a_lyric_come_back_from_the_folder() {
        let mut p = project(4, 1);
        let ids: Vec<u64> = p.parts.iter().map(|t| t.id).collect();
        for (i, part) in p.parts.iter_mut().enumerate().skip(1) {
            Arc::make_mut(part).parent = Some(ids[i - 1]);
        }
        let vocal = Arc::make_mut(&mut p.parts[3]);
        vocal.kind = Some("vocal".parse().unwrap());
        let ClipContent::Midi { notes, .. } = &mut Arc::make_mut(&mut vocal.clips[0]).content else { unreachable!() };
        notes[0].lyric = Some("la".into());
        let (read, files) = kinds_round_trip(&p);
        assert_eq!(canonical(&read), canonical(&p));
        let deepest = &read.parts[3];
        assert_eq!((deepest.kind.as_ref().map(ToString::to_string), deepest.parent), (Some("vocal".into()), Some(ids[2])));
        let text: String = files.values().map(|f| String::from_utf8_lossy(f).into_owned()).collect();
        assert!(text.contains("\"kind\": \"vocal\"") && text.contains("\"parent\""), "the part files name the fields");
    }

    #[test]
    fn an_open_moves_the_old_keys_of_meta_to_their_fields_and_a_save_writes_only_the_fields() {
        let mut old = project(2, 1);
        let group = old.parts[0].id;
        let part = Arc::make_mut(&mut old.parts[1]);
        part.meta.insert("kind".into(), json!("vocal"));
        part.meta.insert("group".into(), json!(group));
        part.meta.insert("color_of_user".into(), json!("kept"));
        let ClipContent::Midi { notes, .. } = &mut Arc::make_mut(&mut part.clips[0]).content else { unreachable!() };
        notes[0].meta.insert("lyric".into(), json!("la"));
        notes[1].meta.insert("lyric".into(), json!(7));
        let (read, _) = kinds_round_trip(&old);
        let part = &read.parts[1];
        assert_eq!(part.kind.as_ref().map(ToString::to_string), Some("vocal".into()));
        assert_eq!(part.parent, Some(group));
        assert_eq!(part.meta.keys().collect::<Vec<_>>(), ["color_of_user"], "an undeclared key stays");
        let ClipContent::Midi { notes, .. } = &part.clips[0].content else { unreachable!() };
        assert_eq!((notes[0].lyric.as_deref(), notes[0].meta.get("lyric")), (Some("la"), None));
        assert_eq!(notes[1].meta.get("lyric"), Some(&json!(7)), "a lyric that is no text stays in meta");
        let (_, files) = kinds_round_trip(&read);
        let text: String = files.values().map(|f| String::from_utf8_lossy(f).into_owned()).collect();
        assert!(!text.contains("\"group\""), "the next save writes no old key");
    }

    #[test]
    fn an_open_tells_of_a_lyric_with_no_note_in_a_clip_file() {
        use crate::session::project_files::MemoryFiles;
        let dir = scratch("stray-lyric");
        let layout = layout(&project(1, 1), &json!({}), None, &dir, &Home::default()).unwrap();
        let mut files: BTreeMap<PathBuf, Vec<u8>> = layout.files.into_iter().collect();
        let (path, clip) = files.iter_mut().find(|(p, _)| p.extension().is_some_and(|e| e == "midi2")).unwrap();
        let path = path.clone();
        // A lyric one tick after the last message, where no note starts,
        // then End of Clip again.
        let end = clip.split_off(clip.len() - 16);
        for w in [0x0040_0001u32, 0xD000_0201, 0x6C61_0000, 0, 0] {
            clip.extend_from_slice(&w.to_be_bytes());
        }
        clip.extend(end);
        let memory = files.iter().map(|(k, v)| (k.clone(), Arc::from(v.as_slice()))).collect();
        let read = read_from(&MemoryFiles::new(&dir, memory), &Home::default(), &dir).unwrap();
        assert_eq!(read.problems, [format!("{}: left out 1 lyrics with no note that starts with them", dir.join(path).display())]);
    }

    /// The export presets of a project are in `project.toml`, not in
    /// `meta.json`, and they come back as they were saved.
    #[test]
    fn export_presets_are_in_project_toml_and_come_back() {
        let dir = scratch("presets");
        let mut p = project(1, 1);
        let presets = json!({ "mine": "stems format=flac", "delivery": ["mix format=flac", "stems"] });
        p.export.insert("presets".into(), presets.clone());
        let layout = layout(&p, &json!({}), None, &dir, &Home::default()).unwrap();
        let text = String::from_utf8(layout.files[Path::new(PROJECT_FILE)].clone()).unwrap();
        assert!(text.contains("[export.presets]"), "{text}");
        assert!(text.contains("mine = \"stems format=flac\""), "{text}");
        assert!(!layout.files.contains_key(Path::new("meta.json")));
        commit(&dir, &layout, None).unwrap();
        let read = read(&Home::default(), &dir).unwrap();
        assert_eq!(read.project.export.get("presets"), Some(&presets));
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The project as canonical text, its notes named as an open names them.
    fn canonical(project: &Project) -> String {
        let mut named = project.clone();
        named.name_notes(&Project::default());
        serde_json::to_string(&named).unwrap()
    }

    #[test]
    fn a_project_comes_back_from_its_files_in_memory() {
        use crate::session::project_files::MemoryFiles;
        let mut show = Project::default();
        let mut part = Part::new(1);
        part.clips = vec![custom(
            2,
            "verse",
            0.0,
            json!({ "kind": "custom", "type": "lyrics", "data": { "text": { "ext": "lrc", "text": "[00:01.00]one" } } }),
        )]
        .into();
        show.parts.push(Arc::new(part));
        // Nothing is on the disk: every file comes from the map.
        let dir = scratch("memory");
        for p in [demo(), project(3, 4), show, chains()] {
            let layout = layout(&p, &json!({ "tempo": 1 }), Some(&json!({ "tabs": [] })), &dir, &Home::default()).unwrap();
            let files = layout.files.into_iter().map(|(k, v)| (k, Arc::from(v))).collect();
            let read = read_from(&MemoryFiles::new(&dir, files), &Home::default(), &dir).unwrap();
            assert!(read.problems.is_empty(), "{:?}", read.problems);
            assert_eq!(canonical(&read.project), canonical(&p));
            assert_eq!((read.transport, read.screen), (json!({ "tempo": 1 }), Some(json!({ "tabs": [] }))));
        }
        assert!(!dir.exists());
    }

    /// A project with splits of several kinds, a macro and its link, taps
    /// and a linked rack with overrides, in the files that paw wrote before
    /// the chain had typed ids: read and written again, each file keeps
    /// its bytes.
    #[test]
    fn the_files_of_a_chain_and_a_linked_rack_keep_their_bytes() {
        use crate::session::project_files::MemoryFiles;
        macro_rules! files {
            ($($path:literal),*) => {
                [$(($path, &include_bytes!(concat!("folder/testdata/chain/", $path))[..])),*]
            };
        }
        let given = files!(
            "project.toml",
            "racks.json",
            "master/devices.json",
            "master/part.json",
            "parts/T1/devices.json",
            "parts/T1/part.json",
            "parts/T2/devices.json",
            "parts/T2/part.json"
        );
        let dir = Path::new("/scratch/song");
        let files = given.iter().map(|(path, bytes)| (PathBuf::from(path), Arc::from(*bytes))).collect();
        let read = read_from(&MemoryFiles::new(dir, files), &Home::default(), dir).unwrap();
        assert!(read.problems.is_empty(), "{:?}", read.problems);
        let layout = layout(&read.project, &read.transport, None, dir, &Home::default()).unwrap();
        for (path, bytes) in given {
            let written = layout.files.get(Path::new(path)).map(|b| String::from_utf8_lossy(b));
            assert_eq!(written.as_deref(), Some(&*String::from_utf8_lossy(bytes)), "{path}");
        }
        assert_eq!(layout.files.len(), given.len(), "no other file");
    }

    /// Two parts whose chains hold the instances of a linked rack.
    fn chains() -> Project {
        use crate::model::ids::{NodeId, PartId};
        use crate::model::owner::OwnerRef;
        use crate::session::{Document, Place, WrapOpts};
        let mut doc = Document::default();
        doc.edit(|p| {
            for (part, device) in [(1, 11), (2, 21)] {
                let mut t = Part::new(part);
                t.name = format!("T{part}");
                let value = json!({ "id": device, "kind": "gain", "bypass": false, "params": { "gain": -2.0 } });
                t.devices.push(Arc::new(serde_json::from_value(value).unwrap()));
                p.parts.push(Arc::new(t));
            }
            Ok(())
        })
        .unwrap();
        doc.next_id = 100;
        let (one, two) = (OwnerRef::Part(PartId::new(1)), OwnerRef::Part(PartId::new(2)));
        let rack = doc.chain_wrap(one, &[NodeId::new(11)], "chain", WrapOpts::default()).unwrap();
        let def = doc.rack_define(one, rack, "Glue").unwrap();
        doc.rack_place(
            two,
            def,
            &Place {
                before: Some(NodeId::new(21)),
                ..Place::default()
            },
        )
        .unwrap();
        doc.project
    }

    /// A chain file in the home folder that the session gives is named
    /// `~/...` in `part.json`, and comes back as the same absolute path.
    /// With no home folder, the project names it by its absolute path.
    #[test]
    fn a_file_in_the_home_folder_is_named_from_it() {
        use crate::session::project_files::MemoryFiles;
        // Paths only: the files stay in memory and the chain file is not
        // there, so the test reads nothing of the machine.
        let dir = Path::new("/scratch/song");
        let chain = PathBuf::from("/scratch/home/chains/lead/devices.json");
        let mut part = Part::new(1);
        part.name = "part".into();
        part.chain_source = Some(chain.clone());
        let mut project = Project::default();
        project.parts.push(Arc::new(part));
        let check = |home: Home, named: &str| {
            let layout = layout(&project, &json!({}), None, dir, &home).unwrap();
            let entry: Value = serde_json::from_slice(&layout.files[Path::new("parts/part/part.json")]).unwrap();
            assert_eq!(entry["devices_file"], json!(named), "the name with {home:?}");
            let files = layout.files.into_iter().map(|(k, v)| (k, Arc::from(v))).collect();
            let read = read_from(&MemoryFiles::new(dir, files), &home, dir).unwrap();
            assert_eq!(read.project.parts[0].chain_source.as_ref(), Some(&chain), "read back with {home:?}");
        };
        check(Home::new(Some("/scratch/home".into())), "~/chains/lead/devices.json");
        check(Home::default(), "/scratch/home/chains/lead/devices.json");
    }

    /// `cargo test --release -p paw-core folder::tests::timing -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn timing() {
        let dir = scratch("timing");
        let p = project(100, 8);
        let layout = layout(&p, &json!({}), None, &dir, &Home::default()).unwrap();
        commit(&dir, &layout, None).unwrap();
        let text = serde_json::to_string_pretty(&p).unwrap();
        let mut folder = Vec::new();
        let mut one = Vec::new();
        for _ in 0..15 {
            let t = std::time::Instant::now();
            let r = read(&Home::default(), &dir).unwrap();
            folder.push(t.elapsed().as_secs_f64() * 1000.0);
            assert_eq!(r.project.parts.len(), 100);
            let t = std::time::Instant::now();
            let q: Project = serde_json::from_str(&text).unwrap();
            one.push(t.elapsed().as_secs_f64() * 1000.0);
            assert_eq!(q.parts.len(), 100);
        }
        folder.sort_by(f64::total_cmp);
        one.sort_by(f64::total_cmp);
        println!(
            "folder read: median {:.2} ms (min {:.2}, max {:.2}); one JSON parse: median {:.2} ms (min {:.2}, max {:.2})",
            folder[7], folder[0], folder[14], one[7], one[0], one[14]
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
}
