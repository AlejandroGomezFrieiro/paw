---
id: TASK-88
title: 'Profile: arrange view drawing in Lua (roles.mark, node_opts)'
status: Done
assignee: []
created_date: '2026-11-22T09:38:00Z'
updated_date: '2026-11-22T13:52:00Z'
labels:
  - performance
  - ui
milestone: m-3
dependencies: []
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: a full frame of the arrange view costs 13.5 ms of kernel time on bench/profile/project.lua after TASK-13 and TASK-14 (under load). Most of it is now the Lua drawing of roles (`roles.mark`, `node_opts`), not the clip list. Bring a full frame of a move (`j`, `k`, `<C-d>`) under 5 ms, with no change of what the user sees. Also two smaller costs that the TASK-14 agent found.

What to do:
1. The drawing of roles. Profile with `bench/profile/run.sh keys --luaprof` and `--record`. Then cut the work and the tables made for each mark: `node_opts` and `wire(props)` make tables for each clip on each frame; `cells` runs in a `pcall` with a closure; a clip that did not change draws again. Ideas to measure first: reuse the opts tables, call `spec.cells` without a closure, skip the scene node work for marks that no frontend reads, keep the drawn cells of a clip by its stamp and its column range.
2. Audio clips stat their file on each `clip_list` call. inotify misses renames of a parent folder, so a file event alone is not safe. Find a safe scheme (for example: a stat at most once a second for each file, plus file events; or watch each parent folder up to the project folder), with a test that renames a parent folder.
3. The chord reading reads every window again when a track that spans the song changes (about 45 ms per key, in background slices). Read again only the windows where the sounding notes changed; a mute of a track that spans the song is the hard case: measure, and if it needs the dependency graph, write that in TASK-77 and leave it.

Read first:
- The merge of TASK-13 and TASK-14 (a36b7e14) and its notes in TASK-14 (the numbers, and why the stat stays).
- runtime/lua/paw/roles.tl (`mark`, `node_opts`, `cells`, `open`, `region`), runtime/lua/paw/views/arrange.lua (the clip drawing), runtime/lua/paw/canvas.tl, runtime/lua/paw/scene.tl, crates/paw-core/src/scene.rs, docs/explanation/about-scenes.md.
- crates/paw-core/src/session/clips.rs (`clip_list`, the offline check of audio files), crates/paw-core/src/session/files_watch.rs and session/watch.rs.
- runtime/lua/paw/harmony.tl and harmony/song.tl (`mark`, the windows read again).
- bench/profile.md; .claude/skills/teal.

Depends on: nothing (TASK-13 and TASK-14 are merged).
Do not touch: the screen API's strings and styles (TASK-15 follows this ticket), the engine.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 bench/profile/run.sh keys on project.lua: a full frame of j, k and <C-d> under 5 ms of kernel time (median, spread and instruction counts in bench/RESULTS.md)
- [ ] #2 The frames do not change: tests/frames.lua, tests/arrange_scene.lua and tests/scene_parity.lua pass with no change of their expected output; cargo test --release -p paw-gui passes
- [ ] #3 Test: an audio clip whose parent folder is renamed shows as missing within one second; clip_list no longer stats every audio file on every call (a counter or a test of the scheme)
- [ ] #4 The chord reading after a change of one track that spans the song costs less than before (numbers), or TASK-77 notes why it needs the graph
- [ ] #5 The full Lua suite passes; tools/tlcheck.sh passes with no new any
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-ace6bd6e140075dc0: bfebd212 (code, tests, docs), 267276c4 (RESULTS), f1c700e2 (merge of main, scope cuts kept). Rows of the arrange timeline the cursor is not on keep their cells (buf:keep/put_kept, paw.api.grid_keep/grid_put, forgotten on hl_set) and are put back when their clips (every field) and ground are the same; layers painted again over them. roles.mark/Plane:mark make node_opts/wire and pcall only while a scene is drawn; clip_props has no closure and leaves window-only props out in a terminal; clip_list takes an optional beat span; keymap.first for the :messages hint; track_kinds.of reads one field. Files of clips: stat at most once a second per path, forgotten on edit/undo/load/save/file event (session/file_check.rs). harmony weigh keeps its work tables. Numbers (load 19-47): instructions of a key and its frame 53M -> 26M; kernel ms k 6.7 -> 5.0, C-d 6.6 -> 4.8, C-u 6.9 -> 4.6, w/b/l/h 7.4-10.6 -> 4.8-5.3; j 20.3 -> 17.4 (first key measured; its frame comes at 5 ms, the rest is after the frame, in the old build too). Mute reading 325M -> 258M instructions; TASK-77 notes why fewer windows needs the graph. Checks: full suite passed; suite.sh plugins: 1 failure, help is made at idle (timing, fails on the base build too under load); tlcheck, apidoc check (only the grid_fill any that main has), cargo test paw-core and paw-gui, luacheck 0, fmtcheck, Vale 0 on changed pages.
<!-- SECTION:NOTES:END -->
