//! A project as a folder of files.
//!
//! ```text
//! song/
//! ├── project.toml            the tempo, the meter, the order of the tracks
//! ├── meta.json               the project's `meta`, when it has some
//! ├── screen.json             the tabs and windows it opens with
//! ├── .gitattributes          `*.midi2 diff=paw-midi2`
//! ├── master/                 the master track, as a track folder
//! ├── tracks/<name>/
//! │   ├── track.json          the track and its clips, without their notes
//! │   ├── devices.json        the chain and its parameters
//! │   ├── <n>-<kind>.state    a plugin's state, as the plugin gives it
//! │   ├── automation/<target>.json
//! │   ├── clips/<name>.midi2  a MIDI 2.0 clip file (crate::clipfile)
//! │   └── clips/<name>.<kind>.json, .signals.json, .sound.midi2
//! │                           the parts of a custom clip (`Writer::custom_clip`)
//! ├── media.json              what each file the clips use is: hash, size, header
//! ├── media/                  sound files, and `derived/` for those a kind makes
//! ├── nests/<name>/           a nest (subproject): see `folder/nests.rs`
//! └── unused/                 files the project does not use any more, and
//!                             `unused/nests/`, the nests no clip places
//! ```
//!
//! [`layout`] turns a project into the bytes of each file, [`commit`]
//! writes the files that changed and moves those the project no longer
//! uses to `unused/` at the same path, and [`read`] puts the project
//! together again. The JSON files are written with their keys in order, so
//! the same project gives the same bytes.

use crate::events::{KernelEvent as E, Saved};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use serde_json::{Map, Value, json};

use super::BASE64;
use super::media::MEDIA_FILE;
use super::project_files::{DiskFiles, ProjectFiles};
use crate::clipfile;
use crate::model::{Clip, ClipContent, KindData, Notes, Project, Target, Track};

mod nests;

/// The file that makes a folder a project.
pub const PROJECT_FILE: &str = "project.toml";
/// The version of the folder's format.
const VERSION: u32 = 2;
/// The folders and the files at the top of a project that paw writes, and
/// so may move to `unused/` when the project does not need them.
const MANAGED_DIRS: [&str; 3] = ["tracks", "master", "nests"];
const MANAGED_FILES: [&str; 3] = ["meta.json", "screen.json", MEDIA_FILE];
const GITATTRIBUTES: &str = "*.midi2 diff=paw-midi2\n";

/// Whether a path names a project kept as a folder: a folder, its
/// `project.toml`, or a name with no extension that is not a file yet.
/// Anything else is a project in one JSON file.
pub fn is_folder_path(path: &Path) -> bool {
    path.file_name().is_some_and(|n| n == PROJECT_FILE)
        || path.is_dir()
        || (!path.exists() && path.extension().is_none())
}

/// Whether `rel`, a path in a project folder, is one of the files that paw
/// writes there: the project file, the files at the top that it manages,
/// and everything under `tracks/` and `master/`.
pub fn is_managed(rel: &Path) -> bool {
    rel.as_os_str() == PROJECT_FILE
        || MANAGED_FILES.iter().any(|f| rel.as_os_str() == *f)
        || rel
            .components()
            .next()
            .is_some_and(|c| MANAGED_DIRS.iter().any(|d| c.as_os_str() == *d))
}

/// The project file as it was before the last save that changed it.
pub fn backup_of(dir: &Path) -> PathBuf {
    dir.join(format!("{PROJECT_FILE}.bak"))
}

/// The `project.toml` of a project folder named by itself or by that file.
pub fn project_file(path: &Path) -> PathBuf {
    if path.file_name().is_some_and(|n| n == PROJECT_FILE) {
        path.to_path_buf()
    } else {
        path.join(PROJECT_FILE)
    }
}

/// A name made of letters, digits, `-`, `_` and `.`, for a file or a
/// folder, that does not start with a dot.
pub fn file_name(name: &str) -> String {
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
fn unique(taken: &mut BTreeSet<String>, stem: &str, ext: &str) -> String {
    let mut name = format!("{stem}{ext}");
    let mut n = 2;
    while taken.contains(&name.to_lowercase()) {
        name = format!("{stem}-{n}{ext}");
        n += 1;
    }
    taken.insert(name.to_lowercase());
    name
}

/// The files of a project, by their path in its folder.
#[derive(Default)]
pub struct Layout {
    pub files: BTreeMap<PathBuf, Vec<u8>>,
    /// The file each clip's notes are in, by clip id: a path in the folder,
    /// or a file outside it the clip refers to.
    pub clip_files: HashMap<u64, PathBuf>,
    /// The folder of each track, by track id.
    pub track_folders: HashMap<u64, PathBuf>,
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
fn lane_stem(target: &Target, track: &Track) -> String {
    match target {
        Target::Volume => "volume".into(),
        Target::Pan => "pan".into(),
        Target::Param { device, param } => {
            let device = track
                .devices
                .iter()
                .position(|d| d.id == *device)
                .map(|i| {
                    let d = &track.devices[i];
                    format!("{}-{}", i + 1, d.name.as_deref().unwrap_or(&d.kind))
                })
                .unwrap_or_else(|| device.to_string());
            file_name(&format!("{device}-{param}"))
        }
        Target::State { device } => {
            let device = track
                .devices
                .iter()
                .position(|d| d.id == *device)
                .map(|i| {
                    let d = &track.devices[i];
                    format!("{}-{}", i + 1, d.name.as_deref().unwrap_or(&d.kind))
                })
                .unwrap_or_else(|| device.to_string());
            file_name(&format!("{device}-state"))
        }
    }
}

/// A clip as `track.json` holds it: everything but its notes, which are in
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
}

impl Writer<'_> {
    fn track(&mut self, track: &Track, folder: &Path) -> Result<()> {
        self.layout
            .track_folders
            .insert(track.id, folder.to_path_buf());
        let mut taken = BTreeSet::new();
        let mut entry = track.clone();
        entry.devices = Vec::new();
        entry.clips = Default::default();
        entry.lanes = Vec::new();
        entry.cues = Default::default();
        let mut value = serde_json::to_value(&entry)?;
        let mut clips = Vec::new();
        for clip in &track.clips {
            clips.push(self.clip(clip, folder, &mut taken)?);
        }
        let mut cues = Vec::new();
        for clip in &track.cues {
            cues.push(self.clip(clip, folder, &mut taken)?);
        }
        // A chain kept in a file outside the folder: named, not written.
        let outside_chain = track.chain_source.as_ref().map(|f| outside_name(f, self.dir));
        let mut devices = Vec::new();
        if outside_chain.is_none() {
            let (chain, states) = chain_files(track)?;
            devices = chain;
            for (name, bytes) in states {
                self.layout.files.insert(folder.join(name), bytes);
            }
        }
        let mut lanes = Vec::new();
        let mut lane_names = BTreeSet::new();
        for lane in &track.lanes {
            let name = unique(&mut lane_names, &lane_stem(&lane.target, track), ".json");
            let rel = Path::new("automation").join(&name);
            self.layout
                .files
                .insert(folder.join(&rel), pretty(&serde_json::to_value(&**lane)?));
            lanes.push(json!(rel));
        }
        let map = value.as_object_mut().context("a track")?;
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
        // The folder a track is in says which nest it belongs to.
        for key in ["source", "chain_source", "nest"] {
            map.remove(key);
        }
        if let Some(chain) = &outside_chain {
            map.insert("devices_file".into(), json!(chain));
        }
        self.layout
            .files
            .insert(folder.join("track.json"), pretty(&value));
        if outside_chain.is_none() {
            self.layout
                .files
                .insert(folder.join("devices.json"), pretty(&Value::Array(devices)));
        }
        Ok(())
    }

    /// Write tracks in order, each in `<root>/tracks/<name>`, and give the
    /// list of their folders' names as `project.toml` and `nest.toml` keep
    /// it: a track folder outside the project is named by its path.
    fn tracks<'t>(
        &mut self,
        tracks: impl Iterator<Item = &'t Arc<Track>>,
        root: &Path,
        mut cache: Option<&mut TrackCache>,
    ) -> Result<Vec<String>> {
        let mut folders = BTreeSet::new();
        let mut order = Vec::new();
        for track in tracks {
            if let Some(source) = &track.source {
                // A track folder outside the project: the project names it and
                // writes nothing of it.
                for clip in track.clips.iter().chain(&track.cues) {
                    if let Some(file) = &clip.source {
                        self.layout.clip_files.insert(clip.id, file.clone());
                    }
                }
                order.push(outside_name(source, self.dir).to_string_lossy().into_owned());
                continue;
            }
            let name = unique(&mut folders, &file_name(&track.name), "");
            let folder = root.join("tracks").join(&name);
            match cache.as_deref_mut() {
                Some(cache) => cache.track(self, track, &folder)?,
                None => self.track(track, &folder)?,
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
            let file = outside_name(source, self.dir);
            self.layout.clip_files.insert(clip.id, source.clone());
            return clip_entry(clip, Some(&file));
        }
        let bytes = clipfile::encode(notes.iter(), controls, clip.length);
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

/// A track's chain as a `devices.json` holds it, and the `.state` file of
/// each plugin's state that it names, by name.
fn chain_files(track: &Track) -> Result<(Vec<Value>, Vec<(String, Vec<u8>)>)> {
    let mut devices = Vec::new();
    let mut files = Vec::new();
    let mut states = BTreeSet::new();
    for (i, device) in track.devices.iter().enumerate() {
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
    /// An audio clip as `track.json` holds it. Its edit list, when it has
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
    /// The file for `bytes` in the track's `clips/`: named `<stem><middle>.<ext>`,
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

    /// A custom clip as `track.json` holds it. Its data, its signals and its
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
            let bytes = clipfile::encode(notes.iter(), controls, clip.length);
            let path = self.clip_file(folder, taken, &stem, ".sound", "midi2", bytes);
            content.insert("sound".into(), json!({ "kind": "midi", "file": path }));
        }
        Ok(value)
    }
}

/// How a project names a file outside its folder: from the home folder as
/// `~/...` when it is there, else the absolute path.
fn outside_name(file: &Path, dir: &Path) -> PathBuf {
    if let Ok(rel) = file.strip_prefix(dir) {
        return rel.to_path_buf();
    }
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from)
        && let Ok(rel) = file.strip_prefix(&home)
    {
        return Path::new("~").join(rel);
    }
    file.to_path_buf()
}

/// A path as a project file gives it, made absolute: `~/` from the home
/// folder, a relative one from the project's folder.
pub fn resolve(file: &Path, dir: &Path) -> PathBuf {
    if let Ok(rel) = file.strip_prefix("~")
        && let Some(home) = std::env::var_os("HOME")
    {
        return PathBuf::from(home).join(rel);
    }
    if file.is_absolute() {
        file.to_path_buf()
    } else {
        tidy(&dir.join(file))
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
pub fn layout(
    project: &Project,
    transport: &Value,
    screen: Option<&Value>,
    dir: &Path,
) -> Result<Layout> {
    lay_out(project, transport, screen, dir, None)
}

/// The files of each track laid out alone, kept from one [`layout_cached`]
/// to the next: states of the undo tree share most of their tracks.
#[derive(Default)]
pub struct TrackCache {
    now: HashMap<(usize, PathBuf), CachedTrack>,
    before: HashMap<(usize, PathBuf), CachedTrack>,
}

struct CachedTrack {
    /// Keeps the track, so that no other track gets its address.
    _track: Arc<Track>,
    files: Vec<(PathBuf, Vec<u8>)>,
}

impl TrackCache {
    /// Put the files of `track` in `folder` into `w`'s layout: from the
    /// cache when the last layout had the very same track there.
    fn track(&mut self, w: &mut Writer<'_>, track: &Arc<Track>, folder: &Path) -> Result<()> {
        let key = (Arc::as_ptr(track) as usize, folder.to_path_buf());
        let entry = match self.now.remove(&key).or_else(|| self.before.remove(&key)) {
            Some(entry) => entry,
            None => {
                // Alone: no file is shared with another track, so the files
                // stay right whatever the other tracks become.
                let mut alone = Writer { layout: Layout::default(), written: HashMap::new(), dir: w.dir };
                alone.track(track, folder)?;
                CachedTrack { _track: Arc::clone(track), files: alone.layout.files.into_iter().collect() }
            }
        };
        for (path, bytes) in &entry.files {
            w.layout.files.insert(path.clone(), bytes.clone());
        }
        w.layout.track_folders.insert(track.id, folder.to_path_buf());
        self.now.insert(key, entry);
        Ok(())
    }
}

/// The files of a project as [`layout`] gives them, except that no two
/// tracks share a file and `clip_files` is empty: for the states of the undo
/// file, which read back as the same project. The tracks that the last call
/// laid out come from `cache`.
pub fn layout_cached(
    project: &Project,
    transport: &Value,
    screen: Option<&Value>,
    dir: &Path,
    cache: &mut TrackCache,
) -> Result<Layout> {
    cache.before = std::mem::take(&mut cache.now);
    lay_out(project, transport, screen, dir, Some(cache))
}

fn lay_out(
    project: &Project,
    transport: &Value,
    screen: Option<&Value>,
    dir: &Path,
    mut cache: Option<&mut TrackCache>,
) -> Result<Layout> {
    let mut w = Writer {
        layout: Layout::default(),
        written: HashMap::new(),
        dir,
    };
    let order = w.tracks(project.song_tracks(), Path::new(""), cache.as_deref_mut())?;
    match cache {
        Some(cache) => cache.track(&mut w, &project.master, Path::new("master"))?,
        None => w.track(&project.master, Path::new("master"))?,
    }
    let nests = w.nests(project)?;
    let mut bare = project.clone();
    bare.master = Arc::new(Track::new(0));
    bare.tracks = Vec::new();
    bare.nests = BTreeMap::new();
    bare.meta = Map::new();
    let mut head = serde_json::to_value(&bare)?;
    let map = head.as_object_mut().context("a project")?;
    map.remove("master");
    map.remove("tracks");
    map.remove("meta");
    map.insert("version".into(), json!(VERSION));
    map.insert("tracks".into(), json!(order));
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
    if let Some(screen) = screen {
        w.layout.files.insert("screen.json".into(), pretty(screen));
    }
    Ok(w.layout)
}

/// What a save did to the files.
#[derive(Debug, Default)]
pub struct Committed {
    /// Paths in the folder that were written, `project.toml` last.
    pub written: Vec<PathBuf>,
    /// Those that were the same already.
    pub unchanged: usize,
    /// Files moved in the folder, as a renamed track's are: (from, to).
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
            .map(|part| s.spawn(move || part.iter().try_for_each(f)))
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
/// moved to where a file of the same bytes is wanted (a renamed track).
pub fn commit(dir: &Path, layout: &Layout, only: Option<&BTreeSet<PathBuf>>) -> Result<Committed> {
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

/// The JSON of a track from its folder, its clips' files still to read:
/// (track, the files its MIDI clips name by the clips' place).
fn read_track(fs: &dyn ProjectFiles, dir: &Path, folder: &Path, problems: &mut Vec<String>) -> Result<Value> {
    let base = dir.join(folder);
    let mut track = read_json(fs, &base.join("track.json"))?;
    // A chain kept in a file outside the folder: the track refers to it.
    let chain_file = track
        .as_object_mut()
        .and_then(|t| t.remove("devices_file"))
        .and_then(|v| v.as_str().map(|s| resolve(Path::new(s), &base)));
    let (chain, chain_source) = match chain_file {
        Some(file) => match read_chain(fs, &file, problems) {
            Ok(chain) => (chain, Some(file)),
            Err(e) => {
                problems.push(format!("{e:#}: the track has no devices until it is there"));
                (Vec::new(), Some(file))
            }
        },
        None => (read_chain(fs, &base.join("devices.json"), problems)?, None),
    };
    let mut lanes = Vec::new();
    if let Some(Value::Array(list)) = track.get("lanes") {
        for name in list {
            let Some(name) = name.as_str() else { continue };
            lanes.push(read_json(fs, &resolve(Path::new(name), &base))?);
        }
    }
    let map = track.as_object_mut().context("a track")?;
    map.insert("devices".into(), Value::Array(chain));
    map.insert("lanes".into(), Value::Array(lanes));
    if let Some(file) = chain_source {
        map.insert("chain_source".into(), json!(file));
    }
    Ok(track)
}

/// The devices of a chain file (a `devices.json`), each with its state
/// read from the file beside it that it names. A file that is not there is
/// an empty chain.
pub fn read_chain(fs: &dyn ProjectFiles, file: &Path, problems: &mut Vec<String>) -> Result<Vec<Value>> {
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
            let path = resolve(Path::new(&name), &base);
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
                let path = resolve(Path::new(name), &base);
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

/// The folder that the clip files of a track folder outside the project are
/// named from: the project that the track folder is in (`<project>/tracks/
/// <name>`), or the track folder itself.
fn track_root(folder: &Path) -> PathBuf {
    match folder.parent() {
        Some(tracks) if tracks.file_name().is_some_and(|n| n == "tracks") => {
            tracks.parent().map(Path::to_path_buf).unwrap_or_default()
        }
        _ => folder.to_path_buf(),
    }
}

/// The ids that a track's JSON gives to the track, its clips, devices and
/// lanes.
fn ids_in(track: &Value, used: &mut BTreeSet<u64>) {
    let id = |v: &Value| v.get("id").and_then(Value::as_u64);
    used.extend(id(track));
    // A chain from a file outside is numbered after the rest.
    let chain = if track.get("chain_source").is_some() { "" } else { "devices" };
    for key in ["clips", "cues", chain, "lanes"] {
        if let Some(Value::Array(list)) = track.get(key) {
            used.extend(list.iter().filter_map(id));
        }
    }
}

/// Give a new id to each part of a track from outside (its devices alone
/// with `devices_only`) whose id a part of the project has, and take the
/// ids. A lane follows its device to its new id.
fn renumber(track: &mut Value, used: &mut BTreeSet<u64>, devices_only: bool) {
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
    if let Some(Value::Array(list)) = track.get_mut("devices") {
        for d in list {
            devices.extend(fresh(d, used));
        }
    }
    if let Some(Value::Array(lanes)) = track.get_mut("lanes") {
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
    if devices_only {
        return;
    }
    fresh(track, used);
    for key in ["clips", "cues"] {
        if let Some(Value::Array(clips)) = track.get_mut(key) {
            for clip in clips {
                fresh(clip, used);
            }
        }
    }
}

/// A track folder outside a project, read as a track that refers to it:
/// with ids the project does not have (`used`), and played into the
/// master with no sends, because the tracks it played into are not here.
pub fn read_outside_track(
    fs: &dyn ProjectFiles,
    folder: &Path,
    used: &mut BTreeSet<u64>,
    problems: &mut Vec<String>,
) -> Result<Value> {
    let mut track = read_track(fs, Path::new(""), folder, problems)
        .with_context(|| format!("reading the track {}", folder.display()))?;
    renumber(&mut track, used, false);
    if let Some(map) = track.as_object_mut() {
        map.insert("source".into(), json!(folder));
        map.insert("output".into(), Value::Null);
        map.insert("sends".into(), json!([]));
        for key in ["origin", "chain_origin"] {
            map.remove(key);
        }
    }
    if let Some(Value::Array(devices)) = track.get_mut("devices") {
        for d in devices {
            if let Some(o) = d.as_object_mut() {
                o.remove("sidechain");
                o.remove("outputs");
            }
        }
    }
    Ok(track)
}

/// Whether a name in `project.toml`'s list of tracks is a track folder
/// outside the project (a path), not a folder in its `tracks`.
fn is_outside_entry(name: &str) -> bool {
    name.contains('/') || name.starts_with('~')
}

/// Take the file a clip's entry names out of it, leaving an empty note
/// list to fill.
fn take_clip_file(fs: &dyn ProjectFiles, clip: &mut Value, files: &mut Vec<(u64, PathBuf)>, dir: &Path) -> Result<()> {
    let id = clip.get("id").and_then(Value::as_u64).unwrap_or(0);
    let Some(content) = clip.get_mut("content") else {
        return Ok(());
    };
    if content.get("kind").and_then(Value::as_str) == Some("custom") {
        return take_custom_files(fs, content, dir);
    }
    if content.get("kind").and_then(Value::as_str) == Some("audio") {
        // An audio clip's edit list, from its file.
        if let Some(file) = content.as_object_mut().and_then(|c| c.remove("edits_file")) {
            let path = resolve(Path::new(file.as_str().unwrap_or_default()), dir);
            content["edits"] = read_json(fs, &path).unwrap_or_else(|_| json!([]));
        }
        return Ok(());
    }
    if content.get("kind").and_then(Value::as_str) != Some("midi") {
        return Ok(());
    }
    if let Some(file) = content.get("file").and_then(Value::as_str) {
        files.push((id, resolve(Path::new(file), dir)));
    }
    *content = json!({ "kind": "midi", "notes": [] });
    Ok(())
}

/// The text of a file that a custom clip's entry names.
fn read_text(fs: &dyn ProjectFiles, file: &str, dir: &Path) -> Result<String> {
    let path = resolve(Path::new(file), dir);
    let bytes = fs.read(&path).with_context(|| format!("reading {}", path.display()))?;
    String::from_utf8(bytes.into_owned()).with_context(|| format!("reading {}", path.display()))
}

/// Put the files that a custom clip's entry names back into it: its data,
/// its signals and its sound when that is MIDI. An error names the file and,
/// for JSON, the line and column.
fn take_custom_files(fs: &dyn ProjectFiles, content: &mut Value, dir: &Path) -> Result<()> {
    let Some(map) = content.as_object_mut() else {
        return Ok(());
    };
    let data = map.get("data").and_then(Value::as_object);
    if let Some(file) = data.and_then(|d| d.get("json_file")).and_then(Value::as_str) {
        let value = read_json(fs, &resolve(Path::new(file), dir))?;
        map.insert("data".into(), json!({ "json": value }));
    } else if let Some(file) = data.and_then(|d| d.get("text_file")).and_then(Value::as_str) {
        let ext = data.and_then(|d| d.get("ext")).cloned().unwrap_or(Value::Null);
        let text = read_text(fs, file, dir)?;
        map.insert("data".into(), json!({ "text": { "ext": ext, "text": text } }));
    }
    if let Some(file) = map.remove("signals_file") {
        let path = resolve(Path::new(file.as_str().unwrap_or_default()), dir);
        map.insert("signals".into(), read_json(fs, &path)?);
    }
    let sound = map.get("sound").and_then(|s| s.get("file")).and_then(Value::as_str);
    if let Some(file) = sound {
        let path = resolve(Path::new(file), dir);
        let bytes = fs.read(&path).with_context(|| format!("reading {}", path.display()))?;
        let read = clipfile::decode(&bytes).with_context(|| format!("reading {}", path.display()))?;
        let midi = ClipContent::Midi { notes: Notes::from(read.notes), controls: read.controls };
        map.insert("sound".into(), serde_json::to_value(&midi)?);
    }
    Ok(())
}

/// Read a project folder (`dir/project.toml`) from the disk.
pub fn read(dir: &Path) -> Result<Read> {
    read_from(&DiskFiles, dir)
}

/// Read the project folder `dir` from `fs`: the disk, or its files in
/// memory.
pub fn read_from(fs: &dyn ProjectFiles, dir: &Path) -> Result<Read> {
    read_with(fs, dir, &dir.join(PROJECT_FILE))
}

/// Read a project folder with `head_path` in place of its `project.toml`
/// (its `.bak`, for one that is damaged).
pub fn read_with(fs: &dyn ProjectFiles, dir: &Path, head_path: &Path) -> Result<Read> {
    let (mut head, order, nest_names, transport) = read_head(fs, head_path)?;
    let mut problems = Vec::new();
    let mut files = Vec::new();
    let mut entries: Vec<TrackEntry> = order.iter().map(|name| TrackEntry::of(name, Path::new(""), None)).collect();
    let mut nests = nests::read_heads(fs, dir, &nest_names, &mut entries)?;
    let (mut tracks, master) = read_all_tracks(fs, dir, &entries, &mut files, &mut problems)?;
    nests::tag_tracks(&mut nests, &entries, &mut tracks)?;
    let map = head
        .as_object_mut()
        .expect("read_head checked that the head is a table");
    map.insert("tracks".into(), Value::Array(tracks));
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
    let screen = read_json(fs, &dir.join("screen.json")).ok();
    let mut project: Project =
        serde_json::from_value(head).with_context(|| format!("reading {}", dir.display()))?;
    let clip_files = fill_clips(fs, &mut project, &files, &mut problems, dir);
    Ok(Read {
        project,
        transport,
        screen,
        clip_files,
        problems,
    })
}

/// The head of a project folder (`project.toml`): the head as JSON
/// without the lists of tracks and nests and the transport, which come
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
    let order: Vec<String> = match map.remove("tracks") {
        Some(v) => {
            serde_json::from_value(v).context("project.toml: tracks is a list of folder names")?
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

/// A track to read: from its folder in the project, or from a track folder
/// outside it, for the song or a nest.
struct TrackEntry {
    /// The folder in the project (`tracks/Bass`, `nests/Bridge/master`), or
    /// the path of one outside it as the list names it.
    folder: PathBuf,
    outside: bool,
    nest: Option<u64>,
    /// The nest's master track (`nests/<name>/master`).
    master: bool,
}

impl TrackEntry {
    /// An entry of a list of tracks (`project.toml`'s, a `nest.toml`'s)
    /// whose folders are in `<root>/tracks`.
    fn of(name: &str, root: &Path, nest: Option<u64>) -> Self {
        if is_outside_entry(name) {
            Self { folder: PathBuf::from(name), outside: true, nest, master: false }
        } else {
            Self { folder: root.join("tracks").join(name), outside: false, nest, master: false }
        }
    }
}

/// Read every track and the master, outside tracks included. The clips'
/// files that the tracks name are collected in `files`.
fn read_all_tracks(
    fs: &dyn ProjectFiles,
    dir: &Path,
    entries: &[TrackEntry],
    files: &mut Vec<(u64, PathBuf)>,
    problems: &mut Vec<String>,
) -> Result<(Vec<Value>, Value)> {
    let mut tracks = Vec::new();
    let fix = |mut track: Value, files: &mut Vec<(u64, PathBuf)>, root: &Path| -> Result<Value> {
        for key in ["clips", "cues"] {
            if let Some(Value::Array(clips)) = track.get_mut(key) {
                for clip in clips {
                    take_clip_file(fs, clip, files, root)?;
                }
            }
        }
        Ok(track)
    };
    // The project's own tracks first: their ids are the project's. What
    // comes from outside (a track folder, a chain file) keeps its ids where
    // no part of the project has them, and gets new ones where one has.
    let mut read_tracks: Vec<Option<Value>> = Vec::new();
    let mut used = BTreeSet::new();
    for entry in entries {
        if entry.outside {
            read_tracks.push(None);
            continue;
        }
        let track = read_track(fs, dir, &entry.folder, problems)
            .with_context(|| format!("reading the track {}", entry.folder.display()))?;
        ids_in(&track, &mut used);
        read_tracks.push(Some(track));
    }
    let mut master = if fs.exists(&dir.join("master/track.json")) {
        read_track(fs, dir, Path::new("master"), problems)?
    } else {
        serde_json::to_value(&*Project::default().master)?
    };
    ids_in(&master, &mut used);
    for track in read_tracks.iter_mut().flatten().chain(std::iter::once(&mut master)) {
        if track.get("chain_source").is_some() {
            renumber(track, &mut used, true);
        }
    }
    for (entry, track) in entries.iter().zip(read_tracks) {
        if let Some(track) = track {
            tracks.push(fix(track, files, dir)?);
            continue;
        }
        // A track folder outside the project: read from where it is.
        let folder = resolve(&entry.folder, dir);
        let track = read_outside_track(fs, &folder, &mut used, problems)?;
        tracks.push(fix(track, files, &track_root(&folder))?);
    }
    let master = fix(master, files, dir)?;
    Ok((tracks, master))
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
    let mut by_path: HashMap<&Path, &Result<clipfile::Clip>> = HashMap::new();
    for (path, clip) in unique.iter().zip(&decoded) {
        by_path.insert(path, clip);
    }
    let mut clip_files = HashMap::new();
    let mut contents: HashMap<u64, (Option<&clipfile::Clip>, PathBuf)> = HashMap::new();
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
        if let Some(read) = read
            && let ClipContent::Midi { notes, controls } = &mut clip.content
        {
            *notes = Notes::from(read.notes.clone());
            *controls = read.controls.clone();
        }
        // A file outside the folder, or one that is missing, stays where
        // the project said it is.
        if !path.starts_with(&tidy_dir) || read.is_none() {
            clip.source = Some(path.clone());
        }
    };
    for track in project
        .tracks
        .iter_mut()
        .chain(std::iter::once(&mut project.master))
    {
        let needs = track
            .clips
            .iter()
            .chain(&track.cues)
            .any(|c| contents.contains_key(&c.id));
        if !needs {
            continue;
        }
        let track = Arc::make_mut(track);
        for clip in &mut track.clips {
            fill(clip);
        }
        for clip in &mut track.cues {
            fill(clip);
        }
    }
    clip_files
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
            .map(|part| s.spawn(move || part.iter().map(one).collect::<Vec<_>>()))
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
        let mut layout = layout(&project, &transport, self.screen.as_ref(), &dir)?;
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
    /// what, track, clip }`. Empty for a project in one file or none.
    pub fn project_files(&mut self) -> Result<Value> {
        let Some((dir, layout)) = self.folder_layout()? else {
            return Ok(json!([]));
        };
        let mut owner: HashMap<&Path, (u64, Option<u64>)> = HashMap::new();
        for (track, folder) in &layout.track_folders {
            owner.insert(folder.as_path(), (*track, None));
        }
        let clip_of: HashMap<&Path, u64> = layout
            .clip_files
            .iter()
            .map(|(id, p)| (p.as_path(), *id))
            .collect();
        let mut out = Vec::new();
        for (rel, bytes) in &layout.files {
            let modified = std::fs::read(dir.join(rel)).map_or(true, |old| &old != bytes);
            let track = rel.ancestors().find_map(|a| owner.get(a).map(|o| o.0));
            let what = match rel.extension().and_then(|e| e.to_str()) {
                Some("midi2") => "clip",
                Some("state") => "state",
                _ if rel.file_name().is_some_and(|n| n == nests::NEST_FILE) => "nest",
                Some("toml") => "project",
                _ if rel.to_string_lossy().ends_with(".edits.json") => "edits",
                _ if rel.to_string_lossy().ends_with(".signals.json") => "signals",
                _ if rel.parent().and_then(Path::file_name).is_some_and(|n| n == "clips") => "data",
                _ if ["tracks", "master", "nests", "unused"].iter().any(|d| rel.starts_with(d))
                    && rel.file_name().is_some_and(|n| n != "meta.json") =>
                {
                    match rel.file_name().and_then(|n| n.to_str()) {
                        Some("track.json") => "track",
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
                "track": track,
                "clip": clip_of.get(rel.as_path()),
            }));
        }
        Ok(Value::Array(out))
    }

    /// Save some of the files of a project kept in a folder, by their path
    /// in it. The project counts as saved when no file differs any more.
    /// Returns the paths written.
    pub fn project_save_files(&mut self, paths: &[PathBuf]) -> Result<Vec<PathBuf>> {
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
                                || (o.file_name().is_some_and(|n| n == "track.json")
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
            self.undo.history.mark_saved(false);
        }
        Ok(done.written)
    }

    /// Open the project kept in a folder: `song`, or `song/project.toml`.
    pub(super) fn project_load_folder(&mut self, path: &Path) -> Result<()> {
        let file = std::path::absolute(project_file(path))?;
        let dir = file.parent().map(Path::to_path_buf).unwrap_or_default();
        let read = read(&dir)?;
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
            self.warnings.push(problem);
        }
        self.undo.touched |= moved;
        Ok(())
    }

    /// Every id the project gives out now, and the next one it will, so that
    /// parts from outside get ids of their own.
    fn used_ids(&self) -> BTreeSet<u64> {
        let mut used = BTreeSet::new();
        for t in self.project.all_tracks() {
            used.insert(t.id);
            used.extend(t.clips.iter().map(|c| c.id));
            used.extend(t.cues.iter().map(|c| c.id));
            used.extend(t.devices.iter().map(|d| d.id));
            used.extend(t.lanes.iter().map(|l| l.id));
        }
        used.insert(self.next_id);
        used
    }

    /// Add the track of a track folder outside the project (one with a
    /// `track.json`), at `index` (from 1; the end when `None`). The project
    /// refers to the folder and keeps no copy, until the track's first edit.
    /// Returns the track's id.
    pub fn track_import_folder(&mut self, folder: &Path, index: Option<usize>) -> Result<u64> {
        let folder = tidy(&std::path::absolute(folder)?);
        if !folder.join("track.json").is_file() {
            bail!("{} is not a track folder: it has no track.json", folder.display());
        }
        let mut used = self.used_ids();
        let mut problems = Vec::new();
        let mut value = read_outside_track(&DiskFiles, &folder, &mut used, &mut problems)?;
        let root = track_root(&folder);
        let mut files = Vec::new();
        for key in ["clips", "cues"] {
            if let Some(Value::Array(clips)) = value.get_mut(key) {
                for clip in clips {
                    take_clip_file(&DiskFiles, clip, &mut files, &root)?;
                }
            }
        }
        let mut track: Track = serde_json::from_value(value).with_context(|| format!("reading {}", folder.display()))?;
        let unique: Vec<PathBuf> = files.iter().map(|(_, p)| p.clone()).collect::<BTreeSet<_>>().into_iter().collect();
        let decoded: HashMap<PathBuf, Result<clipfile::Clip>> = unique.iter().cloned().zip(read_clips(&DiskFiles, &unique)).collect();
        let by_id: HashMap<u64, PathBuf> = files.into_iter().collect();
        for clip in track.clips.iter_mut().chain(track.cues.iter_mut()) {
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
        let id = track.id;
        self.edit(|p| {
            let at = index.map_or(usize::MAX, |i| i.saturating_sub(1)).min(p.tracks.len());
            p.tracks.insert(at, Arc::new(track));
            Ok(())
        })?;
        self.next_id = self.next_id.max(self.project.max_id() + 1);
        self.warnings.extend(problems);
        self.watch_project_files();
        Ok(id)
    }

    /// Give a track the chain of devices in a chain file (a `devices.json`
    /// and the `.state` files beside it). With `refer`, the track refers to
    /// the file and keeps no copy until the chain's first edit; without, the
    /// devices are the track's own at once. Returns how many devices.
    pub fn track_chain_file(&mut self, track: u64, file: &Path, refer: bool) -> Result<usize> {
        let file = tidy(&std::path::absolute(file)?);
        if !file.is_file() {
            bail!("{}: no such chain file", file.display());
        }
        let mut problems = Vec::new();
        let chain = read_chain(&DiskFiles, &file, &mut problems)?;
        let mut used = self.used_ids();
        let mut value = json!({ "devices": chain });
        renumber(&mut value, &mut used, true);
        let devices: Vec<Arc<crate::model::DeviceInst>> =
            serde_json::from_value(value["devices"].take()).with_context(|| format!("reading {}", file.display()))?;
        let count = devices.len();
        self.edit(|p| {
            let t = p.track_mut(track).with_context(|| format!("no track {track}"))?;
            t.devices = devices;
            // Lanes of the devices that went go with them.
            let ids: BTreeSet<u64> = t.devices.iter().map(|d| d.id).collect();
            t.lanes.retain(|l| l.target.device().is_none_or(|d| ids.contains(&d)));
            t.chain_source = refer.then(|| file.clone());
            t.chain_origin = None;
            Ok(())
        })?;
        self.next_id = self.next_id.max(self.project.max_id() + 1);
        self.warnings.extend(problems);
        self.watch_project_files();
        Ok(count)
    }

    /// Write a track's chain of devices as a chain file: `file` (a
    /// `devices.json`) and a `.state` file beside it for each plugin's state.
    /// Returns the files written.
    pub fn chain_write(&mut self, track: u64, file: &Path) -> Result<Vec<PathBuf>> {
        self.capture_states();
        let mut t = self.project.track(track).with_context(|| format!("no track {track}"))?.clone();
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
        let read = read_with(&DiskFiles, &dir, &bak)?;
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
            self.warnings.push(problem);
        }
        // It differs from what is on disk: the project file is damaged.
        self.undo.touched = true;
        self.undo.edits += 1;
        Ok(Value::Null)
    }

    /// Save the project as a folder, at `path` (the folder or its
    /// `project.toml`). With `only`, only those of its files (by their path
    /// in the folder), and the project does not count as saved.
    pub fn project_save_folder(
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
        let named = (self.project.name == Project::default().name)
            .then(|| dir.file_name().map(|s| s.to_string_lossy().into_owned()))
            .flatten()
            .filter(|name| !name.is_empty());
        let mut project = self.file_project(&file);
        if let Some(name) = &named {
            project.name = name.clone();
        }
        let transport = serde_json::to_value(&self.transport)?;
        let mut layout = layout(&project, &transport, self.screen.as_ref(), &dir)?;
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
            self.project.name = name.clone();
            self.undo.checkpoint.name = name;
            self.undo.history.set_current_snapshot(self.undo.checkpoint.clone());
            self.dirty = true;
        }
        if only.is_none() {
            self.undo.history.mark_saved(false);
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
            self.undo.file.saved_files = Some((self.undo.history.current(), layout.files));
        }
        let saved = Saved {
            path: file.clone(),
            written: Some(done.written.clone()),
            unused: Some(done.unused.clone()),
            moved: Some(done.moved.clone()),
        };
        self.emit(E::ProjectSaved(saved));
        Ok((file, done))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Clip, ClipContent, Note, Project, Track};

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
                velocity: 64 + ((i * 13 + seed) % 63) as u8,
                meta: Map::new(),
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

    fn project(tracks: u64, clips: u64) -> Project {
        let mut p = Project::default();
        let mut id = 1;
        for t in 0..tracks {
            let mut track = Track::new(id);
            id += 1;
            track.name = format!("T{t}");
            for c in 0..clips {
                track
                    .clips
                    .push(clip(id, &format!("c{c}"), c as f64 * 4.0, t * 31 + c));
                id += 1;
            }
            p.tracks.push(Arc::new(track));
        }
        p
    }

    fn notes_of(p: &Project) -> Vec<Vec<Note>> {
        p.all_tracks()
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
        let mut track = Track::new(1);
        track.name = "Show".into();
        track.clips = vec![
            custom(2, "intro", 0.0, video.clone()),
            // A split keeps the data: both halves name one data file.
            custom(3, "intro", 4.0, video),
            custom(4, "verse", 8.0, lyrics),
        ]
        .into();
        let mut p = Project::default();
        p.tracks.push(Arc::new(track));
        let first = layout(&p, &json!({}), None, &dir).unwrap();
        let clips = Path::new("tracks/Show/clips");
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
        let read = read(&dir).unwrap();
        assert!(read.problems.is_empty(), "{:?}", read.problems);
        let ClipContent::Custom(video) = &read.project.tracks[0].clips[0].content else {
            panic!("a custom clip");
        };
        assert_eq!(video.data, KindData::Json(data.into()));
        let again = super::layout(&read.project, &json!({}), None, &dir).unwrap();
        assert_eq!(again.files, first.files);
        let ClipContent::Custom(c) = &read.project.tracks[0].clips[2].content else {
            panic!("a custom clip");
        };
        assert_eq!((c.version, c.timeline), (2, crate::model::Timeline::Seconds));
        assert!(commit(&dir, &again, None).unwrap().written.is_empty());
        // A data file that is not JSON is said with its name and the place.
        std::fs::write(dir.join(clips).join("intro.video.json"), "{\n  \"a\": }").unwrap();
        let err = format!("{:#}", read_err(&dir));
        assert!(err.contains("intro.video.json") && err.contains("line 2 column 8"), "{err}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn read_err(dir: &Path) -> anyhow::Error {
        read(dir).err().expect("the data file is not JSON")
    }

    #[test]
    fn a_project_comes_back_from_its_folder() {
        let dir = scratch("round");
        let p = project(3, 4);
        let layout = layout(&p, &json!({}), None, &dir).unwrap();
        commit(&dir, &layout, None).unwrap();
        let read = read(&dir).unwrap();
        assert_eq!(read.project.tracks.len(), 3);
        let mut named = read.project.clone();
        named.name_notes(&Project::default());
        assert!(notes_of(&named) == notes_of(&p), "the notes differ");
        // The same project, the same bytes, and nothing written again.
        let again = super::layout(&read.project, &json!({}), None, &dir).unwrap();
        assert_eq!(again.files, layout.files);
        let done = commit(&dir, &again, None).unwrap();
        assert!(done.written.is_empty(), "{:?}", done.written);
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
        let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/demo-song.json");
        let file: Value = serde_json::from_slice(&std::fs::read(fixture).unwrap()).unwrap();
        let demo: Project = serde_json::from_value(file["project"].clone()).unwrap();
        let mut show = Project::default();
        let mut track = Track::new(1);
        track.clips = vec![custom(
            2,
            "verse",
            0.0,
            json!({ "kind": "custom", "type": "lyrics", "data": { "text": { "ext": "lrc", "text": "[00:01.00]one" } } }),
        )]
        .into();
        show.tracks.push(Arc::new(track));
        // Nothing is on the disk: every file comes from the map.
        let dir = scratch("memory");
        for p in [demo, project(3, 4), show] {
            let layout = layout(&p, &json!({ "tempo": 1 }), Some(&json!({ "tabs": [] })), &dir).unwrap();
            let files = layout.files.into_iter().map(|(k, v)| (k, Arc::from(v))).collect();
            let read = read_from(&MemoryFiles::new(&dir, files), &dir).unwrap();
            assert!(read.problems.is_empty(), "{:?}", read.problems);
            assert_eq!(canonical(&read.project), canonical(&p));
            assert_eq!((read.transport, read.screen), (json!({ "tempo": 1 }), Some(json!({ "tabs": [] }))));
        }
        assert!(!dir.exists());
    }

    /// `cargo test --release -p paw-core folder::tests::timing -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn timing() {
        let dir = scratch("timing");
        let p = project(100, 8);
        let layout = layout(&p, &json!({}), None, &dir).unwrap();
        commit(&dir, &layout, None).unwrap();
        let text = serde_json::to_string_pretty(&p).unwrap();
        let mut folder = Vec::new();
        let mut one = Vec::new();
        for _ in 0..15 {
            let t = std::time::Instant::now();
            let r = read(&dir).unwrap();
            folder.push(t.elapsed().as_secs_f64() * 1000.0);
            assert_eq!(r.project.tracks.len(), 100);
            let t = std::time::Instant::now();
            let q: Project = serde_json::from_str(&text).unwrap();
            one.push(t.elapsed().as_secs_f64() * 1000.0);
            assert_eq!(q.tracks.len(), 100);
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
