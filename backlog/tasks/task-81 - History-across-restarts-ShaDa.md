---
id: TASK-81
title: History across restarts (ShaDa)
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-22T13:25:00Z'
labels:
  - ux
  - editing
milestone: m-4
dependencies: []
priority: medium
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: as Neovim's ShaDa, paw keeps the user's editing state across restarts: the command and search history, the yank registers, the marks, the jump list and the last cursor of each project. Never in the project folder.

What paw keeps today (checked 2026-11-22): the command-line histories are in memory only (runtime/lua/paw/views/cmdline.lua, `histories` by name). Registers, marks and jumps are in memory, per seat (runtime/lua/paw/keymap.lua: `registers`, `marks`, `jumps`, kept by `paw.seats.keep`). The tabs, windows and scopes are in the project's screen.json. The state folder has a folder per project (`paw.loading.project_dir(path)` in runtime/lua/paw/loading.lua).

Decision:
- `state_dir/shada.json` holds what belongs to the user: the histories of each prompt (`:`, `/`, and named prompts), at most `paw.opt.history` entries each (default 200), and the named registers `a` to `z` and `0` when their content is plain data (notes, clips, text, keys) and smaller than 1 MB each.
- `project_dir(path)/shada.json` holds what belongs to a project: the marks, the jump list, the change list and the last cursor (track, beat, view).
- paw reads them at the start and when a project opens, and writes them when paw quits and when a project closes. Two paw instances: the last writer merges by time (as Neovim does), so no entry is lost.
- `paw.opt.shada = true` (default). `false`, `--clean` or a script run (`-l`) read and write nothing.
- Only the local seat's state is kept (a seat that attaches does not write).

Read first: runtime/lua/paw/views/cmdline.lua (histories, near lines 8, 38, 219, 289), runtime/lua/paw/keymap.lua (lines 30 to 85, `setreg` near line 593), runtime/lua/paw/loading.lua (`project_dir`), runtime/lua/paw/recent.lua (a state file, `--clean`), runtime/lua/paw/seats.tl, docs/reference/state-files.md, docs/reference/cmdline.md, docs/reference/markers.md (marks).

Depends on: nothing.
Do not touch: the undo history (TASK-82.1, TASK-82.2), screen.json.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: run :echo 1 and a search /riff, write the state, start a fresh state in the same scratch XDG folders: <Up> at : gives echo 1 and n finds riff
- [ ] #2 Test: yank a clip to register a, write, read again: "ap puts the clip
- [ ] #3 Test: open a project, set mark a and move, close; open it again: 'a goes to the mark and the cursor is where it was
- [ ] #4 Test: two writers with different histories: the file holds the entries of both
- [ ] #5 Test: under --clean and with shada = false nothing is read or written
- [ ] #6 docs/reference/state-files.md and options.md document the files and options; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-ab270b38cd4619ec1. paw/shada.tl (new, Teal): state_dir/shada.json (histories merged by time, last search, registers a-z and 0 under 1 MB, plain data) and project_dir/shada.json (marks, jumps, changes, last cursor and view). Read at start and on project.loaded, written on exit and when a project closes. paw.opt.shada, paw.opt.history. Off under --clean, scripts and shada=false. Tests: tests/shada.lua (5). Docs: state-files.md, options.md. Commit 9ec38602 plus merge of main.
<!-- SECTION:NOTES:END -->
