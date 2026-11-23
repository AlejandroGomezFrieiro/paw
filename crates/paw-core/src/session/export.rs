//! Write a subproject, or a view, as a project folder of its own
//! (`:nest.export <folder>`, `:scope.write <folder>`; `nest.md` 3.6, 4.3).
//! The model makes the project (`model/nest/standalone.rs`); this module
//! writes it with its media copied in. The song does not change, and the
//! session's project file stays the same.

use super::*;
use crate::model::{NestId, Standalone};

use super::folder::{PROJECT_FILE, commit, layout};
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
