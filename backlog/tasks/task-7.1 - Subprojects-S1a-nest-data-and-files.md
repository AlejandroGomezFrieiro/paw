---
id: TASK-7.1
title: 'Subprojects S1a: nest data and files'
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T14:20:00Z'
labels:
  - nest
  - subprojects
milestone: m-2
dependencies: []
parent_task_id: TASK-7
priority: medium
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the data of a subproject (a nest) in the model and in the project folder. No playback and no keys yet: a nest is made through the API in this part.

What to build (nest.md 4.2, 4.3):
- crates/paw-core/src/model.rs: `NestId`, `Nest` (name, length, `NestTempo`, `NestMeter`, master track, order of its tracks, kind, meta with its markers, source, origin), `Project::nests`, `Track::nest`, `ClipContent::Nest { nest, offset, play: NestPlay }`.
- The rules, in `Project::validate`: the nest graph has no cycle and is at most 8 deep (a cycle is refused with its path: `Bridge › Verse › Bridge`); each `NestPlay::Track` names a track of that nest; the output, sends and side-chains of a nest track stay inside its nest (the closed boundary, Q12).
- Files: `nests/<name>/nest.toml`, `meta.json`, `master/`, `tracks/<Name>/…` (track folders as the song has them). Nests are flat under `nests/`, also a nest inside a nest. A nest that no clip uses goes to `unused/nests/` at save; paw never deletes it.
- A small API for the next parts: `api.nest_add`, `nest_get`, `nest_list`, `nest_set`, and `paw.nest` in a new Teal module runtime/lua/paw/nest.tl (`list`, `get`).

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7, 4.1 to 4.3, 4.11. crates/paw-core/src/model.rs (`Project` near line 32, `Track` near line 106, `ClipContent` near line 622, `validate` near line 1575, `check_routing_loops`), crates/paw-core/src/model/custom.rs (how a clip kind is added), crates/paw-core/src/session/folder.rs (`layout`, `commit`, `clip_entry`, `read_track`, `unused_place`), docs/reference/project-files.md, .claude/skills/rust-skills and paw-crates.md.

Depends on: nothing. The ordinal puts it after the view parts, as nest.md 5.2 orders them.
Do not touch: the views, the sync (TASK-7.2, S2a, changes sync/clips.rs).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a project with a nest of two tracks and one nest clip saves, loads and saves again to the same bytes
- [ ] #2 Rust test: a cycle is refused with its path; a nest 9 deep is refused; a nest track that sends to a song bus is refused with a clear message
- [ ] #3 Rust test: a nest that no clip uses is in unused/nests/ after save, and is never deleted
- [ ] #4 The projects in the tests' fixtures open and save unchanged; the Lua suite and cargo test --release -p paw-core pass
- [ ] #5 project-files.md shows nests/ and unused/nests/; api.md is generated again; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a97e2287f2a322e07 (commits 7aa718cd WIP, 4122e193 merge main, 6da2e832 final). model/nest.rs: NestId, Nest, NestTempo, NestMeter, NestPlay, Route; Project::nests (saved as a list), Track::nest, ClipContent::Nest. Rules in Project::validate: no cycle (path in message), at most 8 deep, NestPlay::Track names a track of its nest, closed boundary (output, sends, side-chains, output pairs; also at edit time); the nest master has no output or sends and cannot be removed. Files (session/folder/nests.rs): nests/<name>/nest.toml, meta.json, master/, tracks/; flat; project.toml nests = [...]; a nest the song does not play goes to unused/nests/<name> (next free name if taken), never deleted. API: nest_add, nest_get, nest_list, nest_set, track_add {nest}; paw.nest.list/get (runtime/lua/paw/nest.tl). Design change: no Nest.order; the order of a nest's tracks is their order in Project::tracks. sync/clips.rs: only the two match arms. Not yet: placing a nest from Lua (S3), nest tracks still play at song time and show in track_list (S1b, S2b). AC4: demo-song.json saved as folder and JSON by main and by the branch: byte-identical.
<!-- SECTION:NOTES:END -->
