---
id: TASK-82.2
title: 'Persistent undo 2: the undo file'
status: To Do
assignee: []
created_date: '2026-11-22T09:47:00Z'
updated_date: '2026-11-22T12:38:00Z'
labels:
  - undo
  - editing
milestone: m-4
dependencies:
  - TASK-82.1
parent_task_id: TASK-82
priority: medium
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
- [ ] #1 Test (Lua, scratch XDG folders): make three edits, :w, quit, open the project again: u three times goes back through the three edits, and <C-r> forward
- [ ] #2 Test: a branch made before the save is still in the undo tree after the reopen (api.undo_tree)
- [ ] #3 Test: change a file of the project outside paw, open it: the message comes once and the undo tree starts at the opened state
- [ ] #4 Rust test: two states that change one clip share all other blobs; the undo file of 100 note edits in a 64-track project is smaller than 2 MB
- [ ] #5 Opening bench/profile/project.lua with an undo file of 1 000 states adds less than 50 ms to the open (lazy states); :w adds no time to the kernel thread
- [ ] #6 Under --clean, or with undofile = false, nothing is read or written
- [ ] #7 state-files.md, project-files.md, options.md and the undo how-to document it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Combined into TASK-82.1 (owner, 2026-11-22).
<!-- SECTION:NOTES:END -->
