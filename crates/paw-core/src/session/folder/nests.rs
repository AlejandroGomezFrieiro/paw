//! Nests (subprojects) in a project folder.
//!
//! ```text
//! song/
//! ├── project.toml            `nests = ["Bridge"]`: the nests the song plays
//! ├── nests/
//! │   └── Bridge/
//! │       ├── nest.toml       id, name, length, tempo, meter, kind, the order of its parts
//! │       ├── meta.json       its markers and the data of extensions, if any
//! │       ├── master/         its mix part, as a part folder
//! │       └── parts/<name>/  its parts, as part folders
//! └── unused/nests/<name>/    a nest that no clip places, as at save
//! ```
//!
//! A nest that refers to a project folder outside (`:import`) has a
//! `nest.toml` with its id, its name and the folder (`source`), and no
//! other file: the folder is read again when the song opens
//! (`model/nest/adopt.rs`). The nests that came with it are in the folder,
//! so the song does not list them.
//!
//! Nests are flat under `nests/`, also a nest inside a nest: moving a nest
//! clip changes one line. A nest that the song does not play (no clip
//! places it, or only clips of such nests) is written to `unused/nests/`
//! and is not read back. paw never deletes it: a folder there that holds
//! another nest is left as it is, and the nest takes the next free name.

use super::*;
use crate::model::{Nest, NestId};

/// The file that makes a folder a nest.
pub(super) const NEST_FILE: &str = "nest.toml";

impl Writer<'_> {
    /// Write every nest: in `nests/` those the song plays, in
    /// `unused/nests/` the others. Returns the folder names in `nests/`, as
    /// `project.toml` lists them.
    pub(super) fn nests(&mut self, project: &Project) -> Result<Vec<String>> {
        let used = project.nests_in_use();
        let references = project.references();
        let came_along: BTreeSet<NestId> = references
            .iter()
            .flat_map(|(top, group)| group.iter().filter(move |n| *n != top))
            .copied()
            .collect();
        let mut names = BTreeSet::new();
        let mut unused_names = BTreeSet::new();
        let mut listed = Vec::new();
        for nest in project.nests.values() {
            if used.contains(&nest.id) && references.contains_key(&nest.id) {
                let name = unique(&mut names, &file_name(&nest.name), "");
                self.reference(nest, &Path::new("nests").join(&name))?;
                listed.push(name);
                continue;
            }
            if used.contains(&nest.id) && came_along.contains(&nest.id) {
                continue;
            }
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

    /// The folder of a nest that refers to a project folder: a `nest.toml`
    /// with its id, its name and the folder.
    fn reference(&mut self, nest: &Nest, root: &Path) -> Result<()> {
        let source = nest.source.as_deref().context("a subproject that refers to no folder")?;
        let mut head = toml::Table::new();
        head.insert("id".into(), toml::Value::Integer(i64::try_from(nest.id.0)?));
        head.insert("name".into(), toml::Value::String(nest.name.clone()));
        let source = self.home.outside_name(source, self.dir);
        head.insert("source".into(), toml::Value::String(source.to_string_lossy().into_owned()));
        let text = toml::to_string_pretty(&head).context("writing nest.toml")?;
        self.layout.files.insert(root.join(NEST_FILE), text.into_bytes());
        Ok(())
    }

    /// One nest's folder: `nest.toml`, `meta.json`, `master/`, `parts/`.
    fn nest(&mut self, project: &Project, nest: &Nest, root: &Path) -> Result<()> {
        let parts = project
            .nest_parts(nest.id)
            .filter(|t| t.id != nest.master);
        let order = self.parts(parts, root, None)?;
        let master = project
            .part(nest.master)
            .with_context(|| format!("the master part of the subproject {}", nest.name))?;
        self.part(master, &root.join("master"))?;
        let mut head = serde_json::to_value(nest)?;
        let map = head.as_object_mut().context("a subproject")?;
        // The master is the part in `master/`; the meta is `meta.json`.
        map.remove("master");
        map.remove("meta");
        map.insert("parts".into(), json!(order));
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

/// A nest that refers to a project folder, as its `nest.toml` names it.
pub(super) struct Reference {
    pub id: NestId,
    pub name: String,
    /// The folder, as the file has it: `~/lib/bridge`, or relative to the
    /// song's folder.
    pub source: PathBuf,
}

/// Read the `nest.toml` and `meta.json` of each nest that `project.toml`
/// lists, as the project's JSON has a nest, and add the entries of its
/// parts, then of its master, to `entries`. A nest that refers to a
/// project folder goes to `references`.
pub(super) fn read_heads(
    fs: &dyn ProjectFiles,
    dir: &Path,
    names: &[String],
    entries: &mut Vec<PartEntry>,
    references: &mut Vec<Reference>,
) -> Result<Vec<Value>> {
    let mut out = Vec::new();
    for name in names {
        let root = Path::new("nests").join(name);
        let path = dir.join(&root).join(NEST_FILE);
        let bytes = fs.read(&path).with_context(|| format!("reading {}", path.display()))?;
        let text = std::str::from_utf8(&bytes).with_context(|| format!("reading {}", path.display()))?;
        let head: toml::Value =
            toml::from_str(text).with_context(|| format!("parsing {}", path.display()))?;
        let mut head = from_toml(head);
        let map = head
            .as_object_mut()
            .with_context(|| format!("{} is not a table", path.display()))?;
        let id = map
            .get("id")
            .and_then(Value::as_u64)
            .with_context(|| format!("{} has no id", path.display()))?;
        if let Some(source) = map.get("source").and_then(Value::as_str) {
            let name = map.get("name").and_then(Value::as_str).unwrap_or(name);
            references.push(Reference { id: NestId(id), name: name.to_string(), source: source.into() });
            continue;
        }
        let order: Vec<String> = match map.remove("parts") {
            Some(v) => serde_json::from_value(v)
                .with_context(|| format!("{}: parts is a list of folder names", path.display()))?,
            None => Vec::new(),
        };
        let meta_file = dir.join(&root).join("meta.json");
        let meta = if fs.exists(&meta_file) {
            read_json(fs, &meta_file)?
        } else {
            json!({})
        };
        map.insert("meta".into(), meta);
        entries.extend(order.iter().map(|t| PartEntry::of(t, &root, Some(id))));
        entries.push(PartEntry {
            folder: root.join("master"),
            outside: false,
            nest: Some(id),
            master: true,
        });
        out.push(head);
    }
    Ok(out)
}

/// The project of the folder `folder` as a subproject that `depth` songs
/// refer to reads it: its sound files by their full path, since they are
/// named from that folder. A folder that refers to subprojects deeper than
/// a nest can be is refused: it refers to itself.
pub(in crate::session) fn read_nested(fs: &dyn ProjectFiles, home: &Home, folder: &Path, depth: usize) -> Result<Read> {
    if depth >= crate::model::MAX_DEPTH {
        bail!("{} refers to subprojects more than {} deep: does it refer to itself?", folder.display(), crate::model::MAX_DEPTH);
    }
    let mut read = read_at(fs, home, folder, &folder.join(PROJECT_FILE), depth + 1)?;
    crate::session::media::map_files(&mut read.project, |file| file.is_relative().then(|| tidy(&folder.join(file))));
    Ok(read)
}

/// Make each nest of `references` the project folder it refers to, read
/// again (`model/nest/adopt.rs`). A folder that cannot be read is told,
/// and its nest plays nothing but keeps the folder, so that the song
/// opens and a save keeps the reference.
pub(super) fn adopt_references(
    fs: &dyn ProjectFiles,
    home: &Home,
    dir: &Path,
    project: &mut Project,
    references: Vec<Reference>,
    problems: &mut Vec<String>,
    depth: usize,
) -> Result<()> {
    for r in references {
        let folder = home.resolve(&r.source, dir);
        let sub = match read_nested(fs, home, &folder, depth) {
            Ok(read) => {
                problems.extend(read.problems.into_iter().map(|p| format!("the subproject {}: {p}", r.name)));
                read.project
            }
            Err(e) => {
                problems.push(format!(
                    "the subproject {} refers to {}, which cannot be read ({e:#}): it plays nothing until it is there",
                    r.name,
                    folder.display()
                ));
                Project::default()
            }
        };
        project.adopt(sub, r.id, &r.name, &folder);
    }
    Ok(())
}

/// Tag each part read for a nest with it, and give each nest the id of
/// the part read from its `master/`.
pub(super) fn tag_parts(nests: &mut [Value], entries: &[PartEntry], parts: &mut [Value]) -> Result<()> {
    for (entry, part) in entries.iter().zip(parts.iter_mut()) {
        let Some(nest) = entry.nest else {
            continue;
        };
        part["nest"] = json!(nest);
        if entry.master {
            let head = nests
                .iter_mut()
                .find(|n| n.get("id").and_then(Value::as_u64) == Some(nest))
                .context("a subproject's master without its subproject")?;
            head["master"] = part.get("id").cloned().unwrap_or(Value::Null);
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
        let files = layout(p, &Value::Null, None, dir, &Home::default()).expect("a layout");
        commit(dir, &files, None).expect("saved");
        files
    }

    /// The song plays nest Bridge (10) on its row; Bridge has Keys, with a
    /// MIDI clip, and Strings, and a meter of its own.
    fn ballad() -> Project {
        let mut p = song(10);
        add_nest(&mut p, 10, "Bridge", Vec::new());
        let notes = vec![Note { start: 0.0, length: 1.0, pitch: 60, velocity: crate::model::Velocity(90), meta: Map::new(), id: 1, attr: None }];
        let mut riff: Clip = serde_json::from_value(json!({
            "id": 30, "name": "riff", "start": 0.0, "length": 4.0, "muted": false,
            "content": { "kind": "midi", "notes": [] },
        }))
        .expect("a clip");
        riff.content = ClipContent::Midi { notes: Notes::from(notes), controls: Vec::new() };
        p.part_mut(12).expect("Keys").clips.push(Arc::new(riff));
        let mut strings = Part::new(31);
        strings.name = "Strings".into();
        strings.nest = Some(NestId(10));
        p.parts.push(Arc::new(strings));
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
            "nests/Bridge/master/part.json",
            "nests/Bridge/parts/Keys/part.json",
            "nests/Bridge/parts/Keys/clips/riff.midi2",
            "nests/Bridge/parts/Strings/part.json",
        ] {
            assert!(dir.join(file).is_file(), "{file} is written");
        }
        let read = read(&Home::default(), &dir).expect("read back");
        read.project.validate().expect("valid when read back");
        let again = layout(&read.project, &Value::Null, None, &dir, &Home::default()).expect("a layout");
        assert_eq!(first.files, again.files);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_nest_no_clip_places_goes_to_unused_and_is_never_deleted() {
        let dir = scratch("unused");
        let mut p = ballad();
        save(&p, &dir);
        // The song's clip goes: Bridge is not played any more.
        p.part_mut(1).expect("Ballad").clips = Default::default();
        save(&p, &dir);
        assert!(!dir.join("nests/Bridge").exists());
        assert!(dir.join("unused/nests/Bridge/nest.toml").is_file());
        assert!(dir.join("unused/nests/Bridge/parts/Keys/clips/riff.midi2").is_file());
        assert!(!read(&Home::default(), &dir).expect("read").project.nests.contains_key(&NestId(10)));
        // Another unused nest of the same name keeps the first where it is.
        let mut other = song(40);
        other.part_mut(1).expect("Ballad").clips = Default::default();
        add_nest(&mut other, 40, "Bridge", Vec::new());
        save(&other, &dir);
        assert!(dir.join("unused/nests/Bridge/parts/Keys/clips/riff.midi2").is_file());
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
        let head: toml::Value = toml::from_str(&std::fs::read_to_string(dir.join(PROJECT_FILE)).expect("project.toml"))
            .expect("TOML");
        assert_eq!(head["nests"], toml::Value::Array(vec!["Bridge".into(), "Fill".into()]));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_nest_from_a_folder_is_saved_as_the_path_and_read_from_the_folder_again() {
        let (lib, dir) = (scratch("lib"), scratch("song"));
        // The folder: a song with a subproject of its own.
        save(&ballad(), &lib);
        let mut p = song(100);
        p.adopt(read(&Home::default(), &lib).expect("the folder").project, NestId(100), "Lib", &lib);
        p.validate().expect("a valid song");
        let first = save(&p, &dir);
        let head = std::fs::read_to_string(dir.join("nests/Lib/nest.toml")).expect("nest.toml");
        assert_eq!(head, format!("id = 100\nname = \"Lib\"\nsource = \"{}\"\n", lib.display()));
        assert_eq!(first.files.keys().filter(|f| f.starts_with("nests")).count(), 1, "no copy of it or of the nest inside");
        let back = read(&Home::default(), &dir).expect("read back").project;
        back.validate().expect("valid when read back");
        assert_eq!(layout(&back, &Value::Null, None, &dir, &Home::default()).expect("a layout").files, first.files);
        assert_eq!(back.part(113).map(|t| (t.name.as_str(), t.nest)), Some(("Keys", Some(NestId(111)))), "with the folder's ids from its own");
        // The folder changes: the song plays what it has now.
        let mut changed = ballad();
        changed.part_mut(12).expect("Keys").name = "Piano".into();
        save(&changed, &lib);
        let again = read(&Home::default(), &dir).expect("read again").project;
        assert_eq!(again.part(113).map(|t| t.name.as_str()), Some("Piano"));
        for d in [lib, dir] {
            let _ = std::fs::remove_dir_all(&d);
        }
    }

    #[test]
    fn a_song_whose_subproject_folder_is_gone_opens_and_keeps_the_path() {
        let (lib, dir) = (scratch("gone-lib"), scratch("gone-song"));
        save(&ballad(), &lib);
        let mut p = song(100);
        p.adopt(read(&Home::default(), &lib).expect("the folder").project, NestId(100), "Lib", &lib);
        let first = save(&p, &dir);
        let _ = std::fs::remove_dir_all(&lib);
        let back = read(&Home::default(), &dir).expect("the song opens");
        back.project.validate().expect("valid");
        assert!(back.problems.iter().any(|p| p.contains("it plays nothing until it is there")), "{:?}", back.problems);
        let again = layout(&back.project, &Value::Null, None, &dir, &Home::default()).expect("a layout");
        assert_eq!(again.files.get(Path::new("nests/Lib/nest.toml")), first.files.get(Path::new("nests/Lib/nest.toml")));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
