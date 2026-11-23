//! A subproject and a project folder of its own, both ways (`nest.md`
//! 3.6, 4.3).
//!
//! Out: `:nest.export <folder>` and `:scope.write <folder>` write a
//! subproject, or a view, as a project folder. The model makes the project
//! (`model/nest/standalone.rs`); this module writes it with its media
//! copied in. The song does not change, and the session's project file
//! stays the same.
//!
//! In: `:import <folder>` makes a project folder a subproject that refers
//! to the folder (`model/nest/adopt.rs`); the first edit of it, or
//! `:nest.own`, makes it the song's own copy.

use super::*;
use crate::model::{NestId, Standalone};

use super::folder::{PROJECT_FILE, commit, layout, read_part};
use super::project_files::DiskFiles;
use super::media::MEDIA_FILE;

/// What [`Session::scope_export`] takes: a view, as `paw.scope` gives it.
#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ExportOpts {
    /// The project's name.
    pub name: String,
    /// The tracks of the view, in their order: of one place.
    pub tracks: Vec<Id>,
    /// The time of the view, in the beats of that place.
    pub from: f64,
    pub to: f64,
}

/// What an export wrote, for the Lua side and its message.
#[derive(Debug, Serialize)]
pub struct Exported {
    /// The `project.toml` of the new folder.
    pub path: PathBuf,
    /// Its tracks, without the master and the tracks of subprojects.
    pub tracks: usize,
    /// The media files copied into its `media/`.
    pub media: usize,
    /// The files its clips play that are not there.
    pub missing: Vec<PathBuf>,
    /// The routes cut at the edge of a view, in words.
    pub changes: Vec<String>,
}

impl Session {
    /// Write subproject `nest` as a project folder at `dir` (see the module).
    pub fn nest_export(&mut self, nest: NestId, dir: &Path) -> Result<Exported> {
        let dir = Self::new_folder(dir)?;
        self.capture_states();
        let made = self.doc.project.nest_standalone(nest)?;
        self.write_standalone(made, &dir)
    }

    /// Write the view `opts` as a project folder at `dir` (see the module).
    pub fn scope_export(&mut self, opts: ExportOpts, dir: &Path) -> Result<Exported> {
        let name = opts.name.trim();
        if name.is_empty() {
            bail!("a project needs a name");
        }
        let dir = Self::new_folder(dir)?;
        self.capture_states();
        let made = self.doc.project.view_standalone(name, &opts.tracks, opts.from, opts.to)?;
        self.write_standalone(made, &dir)
    }

    /// `dir` as an absolute path, when it is not there or is empty: an
    /// export never writes over files.
    fn new_folder(dir: &Path) -> Result<PathBuf> {
        if dir.as_os_str().is_empty() {
            bail!("an export needs a folder to write to");
        }
        let dir = folder::tidy(&std::path::absolute(dir)?);
        if dir.is_file() {
            bail!("{} is a file: give a folder", dir.display());
        }
        let full = std::fs::read_dir(&dir).is_ok_and(|mut entries| entries.next().is_some());
        if full {
            bail!("{} has files in it already: give a new or empty folder", dir.display());
        }
        Ok(dir)
    }

    /// Write `made` into the new folder `dir`: its media copied into
    /// `media/`, then its files as a save writes them.
    fn write_standalone(&mut self, made: Standalone, dir: &Path) -> Result<Exported> {
        let Standalone { mut project, changes } = made;
        for track in project.tracks.iter_mut().chain(std::iter::once(&mut project.master)) {
            self.keep_param_ids(track);
        }
        let (media, missing) = self.media_gather(&mut project, dir)?;
        let transport = serde_json::to_value(Transport::default())?;
        let mut files = layout(&project, &transport, None, dir, &self.home)?;
        if !media.is_empty() {
            files.files.insert(MEDIA_FILE.into(), media.to_json());
        }
        commit(dir, &files, None)?;
        Ok(Exported {
            path: dir.join(PROJECT_FILE),
            tracks: project.song_tracks().count(),
            media: media.len(),
            missing,
            changes,
        })
    }
}

impl Session {
    /// Make the project folder `dir` a subproject of the song that refers
    /// to the folder (see the module). Nothing places it yet: the caller
    /// places it in the same undo step. Returns its id.
    pub fn nest_import(&mut self, dir: &Path) -> Result<NestId> {
        let dir = folder::tidy(&std::path::absolute(dir)?);
        let dir = if dir.file_name().is_some_and(|n| n == PROJECT_FILE) {
            dir.parent().map(Path::to_path_buf).unwrap_or_default()
        } else {
            dir
        };
        if !dir.join(PROJECT_FILE).is_file() {
            bail!("{} is not a project folder: it has no {PROJECT_FILE}", dir.display());
        }
        let read = read_part(&DiskFiles, &self.home, &dir, 0)?;
        let name = match read.project.name.trim() {
            "" => dir.file_name().map_or_else(|| "Subproject".into(), |n| n.to_string_lossy().into_owned()),
            name => name.to_string(),
        };
        let id = NestId(self.doc.new_id());
        let mut candidate = self.doc.project.clone();
        candidate.adopt(read.project, id, &name, &dir);
        candidate.validate()?;
        self.edit(|p| {
            *p = candidate;
            Ok(())
        })?;
        self.doc.next_id = self.doc.next_id.max(self.doc.project.max_id() + 1);
        self.doc.warnings.extend(read.problems);
        Ok(id)
    }

    /// Make subproject `nest`, which refers to a project folder, the
    /// song's own copy now, with the subprojects that came with it: each
    /// keeps the folder in `origin`. One undo step. Returns the folder.
    pub fn nest_own(&mut self, nest: NestId) -> Result<PathBuf> {
        let p = &self.doc.project;
        let name = &p.nest(nest).with_context(|| format!("no subproject {nest}"))?.name;
        let Some((top, group)) = p.references().into_iter().find(|(_, g)| g.contains(&nest)) else {
            bail!("{name} is the song's own already: it refers to no folder");
        };
        let source = p.nest(top).and_then(|n| n.source.clone()).unwrap_or_default();
        self.edit(|p| {
            p.own_reference(&group);
            Ok(())
        })?;
        Ok(source)
    }
}
