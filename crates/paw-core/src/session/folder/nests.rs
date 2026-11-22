//! Nests (subprojects) in a project folder.
//!
//! ```text
//! song/
//! ├── project.toml            `nests = ["Bridge"]`: the nests the song plays
//! ├── nests/
//! │   └── Bridge/
//! │       ├── nest.toml       id, name, length, tempo, meter, kind, the order of its tracks
//! │       ├── meta.json       its markers and the data of extensions, if any
//! │       ├── master/         its mix track, as a track folder
//! │       └── tracks/<name>/  its tracks, as track folders
//! └── unused/nests/<name>/    a nest that no clip places, as at save
//! ```
//!
//! Nests are flat under `nests/`, also a nest inside a nest: moving a nest
//! clip changes one line. A nest that the song does not play (no clip
//! places it, or only clips of such nests) is written to `unused/nests/`
//! and is not read back. paw never deletes it: a folder there that holds
//! another nest is left as it is, and the nest takes the next free name.

use super::*;
use crate::model::Nest;

/// The file that makes a folder a nest.
pub(super) const NEST_FILE: &str = "nest.toml";

impl Writer<'_> {
    /// Write every nest: in `nests/` those the song plays, in
    /// `unused/nests/` the others. Returns the folder names in `nests/`, as
    /// `project.toml` lists them.
    pub(super) fn nests(&mut self, project: &Project) -> Result<Vec<String>> {
        let used = project.nests_in_use();
        let mut names = BTreeSet::new();
        let mut unused_names = BTreeSet::new();
        let mut listed = Vec::new();
        for nest in project.nests.values() {
            let root = if used.contains(&nest.id) {
                let name = unique(&mut names, &file_name(&nest.name), "");
                let root = Path::new("nests").join(&name);
                listed.push(name);
                root
            } else {
                unused_folder(self.dir, nest, &mut unused_names)
            };
            self.nest(project, nest, &root)?;
        }
        Ok(listed)
    }

    /// One nest's folder: `nest.toml`, `meta.json`, `master/`, `tracks/`.
    fn nest(&mut self, project: &Project, nest: &Nest, root: &Path) -> Result<()> {
        let tracks = project
            .nest_tracks(nest.id)
            .filter(|t| t.id != nest.master);
        let order = self.tracks(tracks, root)?;
        let master = project
            .track(nest.master)
            .with_context(|| format!("the master track of the subproject {}", nest.name))?;
        self.track(master, &root.join("master"))?;
        let mut head = serde_json::to_value(nest)?;
        let map = head.as_object_mut().context("a subproject")?;
        // The master is the track in `master/`; the meta is `meta.json`.
        map.remove("master");
        map.remove("meta");
        map.insert("tracks".into(), json!(order));
        let head = to_toml(&head).context("a subproject")?;
        let mut text = toml::to_string_pretty(&head).context("writing nest.toml")?;
        if !text.ends_with('\n') {
            text.push('\n');
        }
        self.layout
            .files
            .insert(root.join(NEST_FILE), text.into_bytes());
        if !nest.meta.is_empty() {
            self.layout.files.insert(
                root.join("meta.json"),
                pretty(&Value::Object(nest.meta.clone())),
            );
        }
        Ok(())
    }
}

/// The folder in `unused/nests/` for a nest no clip places: its name, or
/// the next free one (`Bridge-2`) when a folder of that name holds another
/// nest, which stays as it is.
fn unused_folder(dir: &Path, nest: &Nest, taken: &mut BTreeSet<String>) -> PathBuf {
    let stem = file_name(&nest.name);
    let mut n = 1;
    loop {
        let name = if n == 1 {
            stem.clone()
        } else {
            format!("{stem}-{n}")
        };
        n += 1;
        if !taken.insert(name.to_lowercase()) {
            continue;
        }
        let rel = Path::new("unused").join("nests").join(&name);
        if !dir.join(&rel).exists() || id_in(&dir.join(&rel)) == Some(nest.id.0) {
            return rel;
        }
    }
}

/// The id that the `nest.toml` of a nest folder gives.
fn id_in(folder: &Path) -> Option<u64> {
    let text = std::fs::read_to_string(folder.join(NEST_FILE)).ok()?;
    let head: toml::Value = toml::from_str(&text).ok()?;
    head.get("id")?.as_integer()?.try_into().ok()
}

/// Read the `nest.toml` and `meta.json` of each nest that `project.toml`
/// lists, as the project's JSON has a nest, and add the entries of its
/// tracks, then of its master, to `entries`.
pub(super) fn read_heads(
    dir: &Path,
    names: &[String],
    entries: &mut Vec<TrackEntry>,
) -> Result<Vec<Value>> {
    let mut out = Vec::new();
    for name in names {
        let root = Path::new("nests").join(name);
        let path = dir.join(&root).join(NEST_FILE);
        let text = std::fs::read_to_string(&path)
            .with_context(|| format!("reading {}", path.display()))?;
        let head: toml::Value =
            toml::from_str(&text).with_context(|| format!("parsing {}", path.display()))?;
        let mut head = from_toml(head);
        let map = head
            .as_object_mut()
            .with_context(|| format!("{} is not a table", path.display()))?;
        let id = map
            .get("id")
            .and_then(Value::as_u64)
            .with_context(|| format!("{} has no id", path.display()))?;
        let order: Vec<String> = match map.remove("tracks") {
            Some(v) => serde_json::from_value(v)
                .with_context(|| format!("{}: tracks is a list of folder names", path.display()))?,
            None => Vec::new(),
        };
        let meta_file = dir.join(&root).join("meta.json");
        let meta = if meta_file.exists() {
            read_json(&meta_file)?
        } else {
            json!({})
        };
        map.insert("meta".into(), meta);
        entries.extend(order.iter().map(|t| TrackEntry::of(t, &root, Some(id))));
        entries.push(TrackEntry {
            folder: root.join("master"),
            outside: false,
            nest: Some(id),
            master: true,
        });
        out.push(head);
    }
    Ok(out)
}

/// Tag each track read for a nest with it, and give each nest the id of
/// the track read from its `master/`.
pub(super) fn tag_tracks(nests: &mut [Value], entries: &[TrackEntry], tracks: &mut [Value]) -> Result<()> {
    for (entry, track) in entries.iter().zip(tracks.iter_mut()) {
        let Some(nest) = entry.nest else {
            continue;
        };
        track["nest"] = json!(nest);
        if entry.master {
            let head = nests
                .iter_mut()
                .find(|n| n.get("id").and_then(Value::as_u64) == Some(nest))
                .context("a subproject's master without its subproject")?;
            head["master"] = track.get("id").cloned().unwrap_or(Value::Null);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::nest::tests::{add_nest, nest_clip, song};
    use crate::model::{Note, NestId};

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "paw-nests-{name}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    fn save(p: &Project, dir: &Path) -> Layout {
        let files = layout(p, &Value::Null, None, dir).expect("a layout");
        commit(dir, &files, None).expect("saved");
        files
    }

    /// The song plays nest Bridge (10) on its row; Bridge has Keys, with a
    /// MIDI clip, and Strings, and a meter of its own.
    fn ballad() -> Project {
        let mut p = song(10);
        add_nest(&mut p, 10, "Bridge", Vec::new());
        let notes = vec![Note { start: 0.0, length: 1.0, pitch: 60, velocity: 90, meta: Map::new(), id: 1, attr: None }];
        let mut riff: Clip = serde_json::from_value(json!({
            "id": 30, "name": "riff", "start": 0.0, "length": 4.0, "muted": false,
            "content": { "kind": "midi", "notes": [] },
        }))
        .expect("a clip");
        riff.content = ClipContent::Midi { notes: Notes::from(notes), controls: Vec::new() };
        p.track_mut(12).expect("Keys").clips.push(Arc::new(riff));
        let mut strings = Track::new(31);
        strings.name = "Strings".into();
        strings.nest = Some(NestId(10));
        p.tracks.push(Arc::new(strings));
        let bridge = p.nest_mut(NestId(10)).expect("Bridge");
        bridge.meter = serde_json::from_value(json!({ "mode": "own", "changes": [{ "beat": 0.0, "num": 6, "den": 8 }] }))
            .expect("a meter");
        bridge.meta.insert("markers".into(), json!([{ "id": 1, "beat": 8.0, "name": "Lift" }]));
        p.validate().expect("a valid project");
        p
    }

    #[test]
    fn a_project_with_a_nest_saves_loads_and_saves_again_to_the_same_bytes() {
        let dir = scratch("round");
        let first = save(&ballad(), &dir);
        for file in [
            "nests/Bridge/nest.toml",
            "nests/Bridge/meta.json",
            "nests/Bridge/master/track.json",
            "nests/Bridge/tracks/Keys/track.json",
            "nests/Bridge/tracks/Keys/clips/riff.midi2",
            "nests/Bridge/tracks/Strings/track.json",
        ] {
            assert!(dir.join(file).is_file(), "{file} is written");
        }
        let read = read(&dir).expect("read back");
        read.project.validate().expect("valid when read back");
        let again = layout(&read.project, &Value::Null, None, &dir).expect("a layout");
        assert_eq!(first.files, again.files);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_nest_no_clip_places_goes_to_unused_and_is_never_deleted() {
        let dir = scratch("unused");
        let mut p = ballad();
        save(&p, &dir);
        // The song's clip goes: Bridge is not played any more.
        p.track_mut(1).expect("Ballad").clips = Default::default();
        save(&p, &dir);
        assert!(!dir.join("nests/Bridge").exists());
        assert!(dir.join("unused/nests/Bridge/nest.toml").is_file());
        assert!(dir.join("unused/nests/Bridge/tracks/Keys/clips/riff.midi2").is_file());
        assert!(!read(&dir).expect("read").project.nests.contains_key(&NestId(10)));
        // Another unused nest of the same name keeps the first where it is.
        let mut other = song(40);
        other.track_mut(1).expect("Ballad").clips = Default::default();
        add_nest(&mut other, 40, "Bridge", Vec::new());
        save(&other, &dir);
        assert!(dir.join("unused/nests/Bridge/tracks/Keys/clips/riff.midi2").is_file());
        assert_eq!(id_in(&dir.join("unused/nests/Bridge")), Some(10));
        assert_eq!(id_in(&dir.join("unused/nests/Bridge-2")), Some(40));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_nest_inside_a_nest_is_flat_under_nests() {
        let dir = scratch("flat");
        let mut p = song(10);
        add_nest(&mut p, 10, "Bridge", vec![nest_clip(20, 40, 0.0, json!("master"))]);
        add_nest(&mut p, 40, "Fill", Vec::new());
        save(&p, &dir);
        assert!(dir.join("nests/Fill/nest.toml").is_file());
        let head = std::fs::read_to_string(dir.join(PROJECT_FILE)).expect("project.toml");
        assert!(head.contains(r#"nests = ["Bridge", "Fill"]"#), "{head}");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
