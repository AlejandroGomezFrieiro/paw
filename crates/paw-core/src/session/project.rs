//! Opening and saving the project, and the project file. The project's
//! own fields are in `session/document/project.rs`.

use crate::events::{KernelEvent as E, Loaded, Saved};
use super::*;

impl Session {
    /// The project's fields as a table ([`Document::project_view`]).
    pub fn project_view(&self) -> Value {
        self.doc.project_view(self.path.as_deref())
    }

    /// One entry of [`project_view`](Self::project_view)
    /// ([`Document::project_field`]).
    pub fn project_field(&self, key: &str) -> Value {
        self.doc.project_field(key, self.path.as_deref())
    }

    pub fn project_set(&mut self, key: &str, value: Value) -> Result<()> {
        self.doc.project_set(key, value, self.path.as_deref())
    }




    /// Put the open project aside, history and all, and open an empty
    /// scratch project in its place, for something that needs tracks and
    /// clips of its own (a hardware check) without touching the user's work.
    /// [`project_unshelve`](Self::project_unshelve) puts it back exactly as
    /// it was, undo tree included.
    pub fn project_shelve(&mut self) -> Result<()> {
        if self.shelf.is_some() {
            bail!("a project is put aside already");
        }
        self.capture_states();
        self.checkpoint();
        self.doc.undo.history.set_current_snapshot(self.doc.undo.checkpoint.clone());
        let fresh = Project::default();
        let limits = (self.doc.undo.history.limit(), self.doc.undo.history.byte_limit());
        let history = std::mem::replace(&mut self.doc.undo.history, new_history(fresh.clone(), limits));
        self.shelf = Some(Shelf {
            project: self.doc.project.clone(),
            history,
            touched: self.doc.undo.touched,
            transport: self.transport.clone(),
            position: self.position(),
            path: self.path.clone(),
            lazy: self.undo_file_swap(Default::default()),
        });
        self.replace_project(fresh, Transport::default(), None);
        Ok(())
    }

    /// Whether a project is put aside by [`project_shelve`](Self::project_shelve).
    pub fn project_shelved(&self) -> bool {
        self.shelf.is_some()
    }

    /// Close the scratch project and bring back the one put aside.
    pub fn project_unshelve(&mut self) -> Result<()> {
        let Some(shelf) = self.shelf.take() else {
            bail!("no project is put aside");
        };
        let limits = (self.doc.undo.history.limit(), self.doc.undo.history.byte_limit());
        self.doc.undo.history = shelf.history;
        self.undo_file_swap(shelf.lazy);
        self.doc.undo.history.set_limits(limits.0, limits.1);
        self.put_project(shelf.project, shelf.transport, shelf.path, Some(shelf.touched));
        self.seek(shelf.position);
        Ok(())
    }

    /// Replace the project, dropping the undo history.
    pub(super) fn replace_project(
        &mut self,
        project: Project,
        transport: Transport,
        path: Option<PathBuf>,
    ) {
        self.put_project(project, transport, path, None);
    }

    /// Make `project` the open one. With `touched`, the undo history is
    /// already in place and kept; without, it starts again from the project.
    pub(super) fn put_project(
        &mut self,
        mut project: Project,
        transport: Transport,
        path: Option<PathBuf>,
        touched: Option<bool>,
    ) {
        project.refresh_tempo();
        // The clips of a link read their notes each on their own from a
        // project file: in memory they share them.
        project.join_links();
        self.apply_open_opts(&mut project);
        // Another project: a trial of this one's is over with it, and so
        // are the files that played its tracks. A held id could name a
        // track of the new project.
        self.audition.trial = None;
        self.engine.map.held_files.clear();
        self.stop();
        // A take that closes belongs to this project, not the next one.
        self.finish_takes_now();
        self.seek(0.0);
        self.doc.next_id = self.doc.next_id.max(project.max_id() + 1);
        self.doc.project = project;
        self.files_there.forget();
        self.doc.undo.checkpoint = self.doc.project.clone();
        if touched.is_none() {
            self.doc.undo.history.reset(self.doc.project.clone(), history::now());
            // Its states from an undo file went with it.
            self.undo_file_swap(Default::default());
        }
        self.doc.undo.touched = touched.unwrap_or(false);
        // Another project is a change: what Lua keeps by the count of edits
        // (paw/groups.tl, paw/scope.tl) reads the new project at once, not at
        // the end of the turn when `project.loaded` is sent.
        self.doc.undo.edits += 1;
        self.doc.dirty = true;
        self.doc.undo.restoring = true;
        // The count-in is the user's, not the project's.
        let (count_in, pre_roll, pre_roll_seconds) = (
            self.transport.count_in,
            self.transport.pre_roll,
            self.transport.pre_roll_seconds,
        );
        self.transport = Transport {
            count_in,
            pre_roll,
            pre_roll_seconds,
            ..transport
        };
        self.path = path;
        // Another project opens with its own screen, if it keeps one.
        self.screen = None;
        self.send_transport();
        self.flush();
        self.cue_reset();
        // The old project's audio is not needed for undo any more.
        self.trim_audio();
        self.watch_project_files();
        self.doc.emit(E::ProjectLoaded(Loaded { path: self.path.clone() }));
    }

    pub fn project_new(&mut self) {
        self.replace_project(Project::default(), Transport::default(), None);
    }

    /// Start the undo history again from the project as it is now, which
    /// counts as unchanged: for a project put together by a script from a
    /// file that is not a project, such as a MIDI file, which then opens as
    /// a project file does instead of as edits of an empty one.
    /// Count the project as it is now as saved, without writing it.
    pub fn mark_saved(&mut self) {
        self.checkpoint();
        self.doc.undo.history.mark_saved(false);
    }

    /// Count the project as changed, so that it asks to be saved, with no
    /// undo step: for data that a save writes and undo does not keep, such
    /// as the workspaces of the project's screen.
    pub fn mark_changed(&mut self) {
        self.doc.undo.touched = true;
        self.doc.undo.edits += 1;
    }

    pub fn project_load(&mut self, path: &Path) -> Result<()> {
        if folder::is_folder_path(path) {
            return self.project_load_folder(path);
        }
        let text =
            std::fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
        let mut file: ProjectFile =
            serde_json::from_str(&text).with_context(|| format!("parsing {}", path.display()))?;
        if file.version > FILE_VERSION {
            bail!("{} was saved by a newer version", path.display());
        }
        file.project
            .validate()
            .with_context(|| format!("{} cannot be loaded", path.display()))?;
        let moved = self.find_media(&mut file.project, path);
        self.replace_project(file.project, file.transport, Some(path.to_path_buf()));
        self.screen = file.screen;
        // Files found elsewhere are a change the file does not have yet.
        self.doc.undo.touched |= moved;
        Ok(())
    }

    /// Write the project as it is now to `path`, without making that the
    /// project's file or counting it as saved: a safety copy. `note` goes
    /// into the file as `recovery`, for whoever finds it later.
    pub fn project_backup(&mut self, path: &Path, note: Value) -> Result<()> {
        self.capture_states();
        let file = json!({
            "version": FILE_VERSION,
            "project": self.doc.project,
            "transport": self.transport,
            "take": self.take_in_progress(),
            "recovery": note,
        });
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
        }
        crate::safe::write_file(path, serde_json::to_string(&file)?.as_bytes(), false)?;
        Ok(())
    }

    /// Open a safety copy as the project it was a copy of: with that
    /// project's file name (none if it never had one), and as changed since
    /// it was last saved. Returns the note the copy was written with.
    /// With `as_path`, the copy opens under that file name instead (for a
    /// `.bak` or any other copy that has no note).
    pub fn project_recover(&mut self, path: &Path, as_path: Option<&Path>) -> Result<Value> {
        if path.file_name().and_then(|n| n.to_str()) == Some(&format!("{}.bak", folder::PROJECT_FILE)) {
            return self.project_recover_folder(path);
        }
        let text =
            std::fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
        let mut value: Value =
            serde_json::from_str(&text).with_context(|| format!("parsing {}", path.display()))?;
        let note = value
            .as_object_mut()
            .and_then(|o| o.remove("recovery"))
            .unwrap_or(Value::Null);
        let take = value
            .as_object_mut()
            .and_then(|o| o.remove("take"))
            .unwrap_or(Value::Null);
        let mut file: ProjectFile =
            serde_json::from_value(value).with_context(|| format!("parsing {}", path.display()))?;
        if file.version > FILE_VERSION {
            bail!("{} was saved by a newer version", path.display());
        }
        file.project
            .validate()
            .with_context(|| format!("{} cannot be recovered", path.display()))?;
        let original = as_path
            .map(Path::to_path_buf)
            .or_else(|| note["path"].as_str().map(PathBuf::from));
        // A `.bak` names files relative to the project, as the project does;
        // and either may have moved with the project's folder.
        if let Some(original) = &original {
            self.find_media(&mut file.project, original);
        }
        self.replace_project(file.project, file.transport, original);
        self.restore_take(&take);
        // It differs from what is on disk, if anything is.
        self.doc.undo.touched = true;
        self.doc.undo.edits += 1;
        Ok(note)
    }

    /// The project as a file at `path` holds it: media named as from
    /// there, and the devices' own ids of the parameters it names.
    pub(super) fn file_project(&self, path: &Path) -> Project {
        let mut project = media::for_file(&self.doc.project, path);
        let tracks = project
            .tracks
            .iter_mut()
            .chain(std::iter::once(&mut project.master));
        for track in tracks {
            self.keep_param_ids(track);
        }
        project
    }

    /// Note in each device of a track that is about to be written the
    /// device's own id of each parameter key that it or its lanes use (see
    /// `DeviceInst::param_ids`), for every place a chain is written.
    pub(crate) fn keep_param_ids(&self, track: &mut Arc<Track>) {
        let mut found = Vec::new();
        for (at, d) in track.devices.iter().enumerate() {
            let Some(live) = self.live.get(&d.id) else { continue };
            let lanes = track.lanes.iter().filter_map(|l| match &l.target {
                Target::Param { device, param } if *device == d.id => Some(param),
                _ => None,
            });
            let mut ids = d.param_ids.clone();
            for key in d.params.keys().chain(lanes) {
                let Some(p) = live.params.iter().find(|p| &p.key == key) else { continue };
                if !p.id.is_empty() && p.id != p.key {
                    ids.insert(key.clone(), p.id.clone());
                }
            }
            if ids != d.param_ids {
                found.push((at, ids));
            }
        }
        if found.is_empty() {
            return;
        }
        let track = Arc::make_mut(track);
        for (at, ids) in found {
            Arc::make_mut(&mut track.devices[at]).param_ids = ids;
        }
    }

    pub fn project_save(&mut self, path: Option<&Path>) -> Result<PathBuf> {
        // An empty path would save into the current folder.
        if path.is_some_and(|path| path.as_os_str().is_empty()) {
            bail!("a project needs a path to save to, not an empty one");
        }
        let path = path
            .map(Path::to_path_buf)
            .or_else(|| self.path.clone())
            .context("the project has no file yet: give a path")?;
        if folder::is_folder_path(&path) {
            return self.project_save_folder(&path, None).map(|(path, _)| path);
        }
        self.adopt_recordings(&path)?;
        self.capture_states();
        // What is saved is everything up to here and nothing after: an edit
        // made later in the same turn is a change that is not saved.
        self.checkpoint();
        // A project that was never named takes its file's name.
        let named = (self.doc.project.name == Project::default().name)
            .then(|| path.file_stem().map(|s| s.to_string_lossy().into_owned()))
            .flatten()
            .filter(|name| !name.is_empty());
        let mut project = self.file_project(&path);
        if let Some(name) = &named {
            project.name = name.clone();
        }
        let file = ProjectFile {
            version: FILE_VERSION,
            project,
            transport: self.transport.clone(),
            screen: self.screen.clone(),
        };
        let text = serde_json::to_string_pretty(&file)?;
        // Write beside the target, flush it and rename, so a crash cannot
        // leave half a file; what was there before is kept as `.bak`.
        crate::safe::write_file(&path, text.as_bytes(), true)?;
        self.path = Some(path.clone());
        if let Some(name) = named {
            // Not an edit to undo: the saved state is the named one.
            self.doc.project.name = name.clone();
            self.doc.undo.checkpoint.name = name;
            self.doc.undo.history.set_current_snapshot(self.doc.undo.checkpoint.clone());
            self.doc.dirty = true;
        }
        self.doc.undo.history.mark_saved(false);
        self.remember_for_panic();
        let saved = Saved { path: path.clone(), written: None, unused: None, moved: None };
        self.doc.emit(E::ProjectSaved(saved));
        Ok(path)
    }
}
