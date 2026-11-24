---
id: TASK-82.1
title: 'Persistent undo: read a project folder from memory, and the undo file'
status: Done
assignee: []
created_date: '2026-11-22T09:47:00Z'
updated_date: '2026-11-22T14:48:00Z'
labels:
  - undo
  - refactor
milestone: m-4
dependencies: []
parent_task_id: TASK-82
priority: medium
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Combined ticket (owner, 2026-11-22): one agent builds TASK-82.1, TASK-82.2 in order, with one build, one suite run and one merge. Commit after each part.

Goal: paw reads a project folder from files in memory, not only from the disk. This is a seam that the persistent undo needs (TASK-82.2), and also the browser build (backlog/docs/designs/web.md, the projects and files part) and the checkpoints.

Today: crates/paw-core/src/session/folder.rs makes the files of a project in memory (`layout()` gives a `Layout`), and `commit()` writes them. The reader (`read_track`, `read_chain`, `read_json` and the functions near them) reads paths on the disk.

What to do: a small trait for the reader, for example `trait ProjectFiles { fn read(&self, rel: &Path) -> Result<Vec<u8>>; fn list(&self, rel: &Path) -> Result<Vec<PathBuf>>; }`, with one implementation for a folder on the disk and one for a map of files in memory (`BTreeMap<PathBuf, Arc<[u8]>>`, the form that `layout()` gives). The reader takes `&dyn ProjectFiles`. Media files stay on the disk (they are not in the map); only the project's own files go through the trait.

Read first: crates/paw-core/src/session/folder.rs (all of it: `layout`, `commit`, the read functions), crates/paw-core/src/session/project.rs (open and save), .claude/skills/rust-skills (traits, no long functions with flags) and .claude/skills/rust-skills/paw-crates.md.

Depends on: nothing.
Do not touch: the format of the files (no change of any file), the undo history.

Size: S.

## Part of TASK-82.2: Persistent undo 2: the undo file

Goal: as Neovim's undofile, the user opens a project again and can still undo past the last save, and go to the states and branches of the undo tree from earlier sessions.

Decision:
- The undo file is in the state folder, not in the project: `paw.loading.project_dir(path)/undo/`. (Not shared through git, as Neovim's undofile is not.)
- Content-addressed: each file of a state's layout (from `layout()`) is a blob named by its BLAKE3 hash (`blobs/ab/abcd…`). A state is a manifest: path to hash. Unchanged files are shared between states, so a state costs about what its edit changed. `tree.json` holds each state's id, parent, children, redo child, time, label, keys, name, `keep`, manifest hash, and which state is saved.
- paw writes the undo file at `:w`, on a worker thread, after the project is saved: the states that are new since the last write. Then it removes blobs that no state uses.
- When a project opens, paw reads `tree.json`. When the saved state's manifest matches the files of the project on the disk, the old states come back. They stay on the disk until the user goes to one (lazy: an `undo_goto` reads the manifest through TASK-82.1's reader). When the files do not match (a change outside paw, a git checkout), paw does not read the undo file and says so once: `the undo file is for another version of the project: not read`.
- Limits: `paw.opt.undofile = true` (default), `paw.opt.undofile_mb = 256` per project. Past the limit, the oldest states that are not protected go first (as the History prunes today).
- `:undolist` and the undo tree view (the undotree extension) show the old states.

Read first: crates/paw-core/src/history.rs (states, pruning, protected states, `weigh`), crates/paw-core/src/session/undo.rs (`undo_project`, `checkpoint_write`, `checkpoint_restore`), crates/paw-core/src/session/folder.rs (`layout`) and TASK-82.1's reader, crates/paw-core/src/bake (BLAKE3 use), runtime/lua/paw/loading.lua (`project_dir`), docs/reference/project-files.md, docs/reference/state-files.md, docs/how-to/undo-and-return-to-an-earlier-state.md, extensions/undotree.

Depends on: TASK-82.1.
Do not touch: the project folder's files and format.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 (82.1) Rust test: for the projects in the tests' fixtures, layout() then a read from the map in memory gives a project whose canonical text equals the original's
- [ ] #2 (82.1) Opening a project from the disk does not change: the Lua suite and cargo test --release -p paw-core pass
- [ ] #3 (82.1) Opening a large project (bench/profile/project.lua, saved) takes no more time than before (bench/saveload.lua, median of 5, spread given)
- [ ] #4 (82.2) Test (Lua, scratch XDG folders): make three edits, :w, quit, open the project again: u three times goes back through the three edits, and <C-r> forward
- [ ] #5 (82.2) Test: a branch made before the save is still in the undo tree after the reopen (api.undo_tree)
- [ ] #6 (82.2) Test: change a file of the project outside paw, open it: the message comes once and the undo tree starts at the opened state
- [ ] #7 (82.2) Rust test: two states that change one clip share all other blobs; the undo file of 100 note edits in a 64-track project is smaller than 2 MB
- [ ] #8 (82.2) Opening bench/profile/project.lua with an undo file of 1 000 states adds less than 50 ms to the open (lazy states); :w adds no time to the kernel thread
- [ ] #9 (82.2) Under --clean, or with undofile = false, nothing is read or written
- [ ] #10 (82.2) state-files.md, project-files.md, options.md and the undo how-to document it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built both parts on branch worktree-agent-a1e6c8bae2c3618f6. Commits: 9141893c (82.1: ProjectFiles reader trait, DiskFiles and MemoryFiles, folder::read_from), 4a237d34 (82.2: the undo file: crate::undofile store, session/undo_file.rs, paw/undofile.tl, options undofile and undofile_mb, docs), 692178b1 (merge main, with TASK-81 shada conflicts in options.tl, options.md and state-files.md resolved by keeping both). Undo file is content-addressed (BLAKE3 blobs, a blob per folder), written on a worker thread after :w, read lazily at open. undofile is false under --clean, as autosave is. Only project folders have an undo file (layout is folder-only). Numbers measured under external load: open of the bench project with 1000 states: undo_file_open median 7.5 ms (6.1 to 10.7), full open +34 ms median; save not slower (35.7 vs 35.9 ms median); first write of 1000 states 8.4 s on the worker; 27 MB on disk. 100 note edits in 64 tracks: 804 kB. Full suite with plugins passed (1828), cargo test -p paw-core passed (153).
<!-- SECTION:NOTES:END -->
