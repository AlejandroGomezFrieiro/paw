---
id: TASK-7.16
title: >-
  Subprojects S12a part 2: :import of a project folder as a subproject,
  :nest.own, and :e of a path inside a song
status: Done
assignee: []
created_date: '2026-11-23T06:13:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - nest
  - subprojects
milestone: m-2
dependencies:
  - TASK-7.14
parent_task_id: TASK-7
priority: high
ordinal: 229000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: a project folder comes into the song as a subproject, and a path inside a song opens that subproject. Split from TASK-7.14 on 2026-11-23.

User-visible behavior (nest.md 3.6, 3.7 table, 4.3; Q10):
- :import <folder> places a subproject that refers to the folder (source). It plays at once.
- The first edit inside it makes it the song's own copy, says so once, and keeps the path in origin. :nest.own makes the copy now. Each is one undo step.
- :e song/nests/Bridge opens the song and enters Bridge.

Read first: Design: backlog/docs/designs/nest.md, sections 3.6, 3.7, 4.3; the owner accepted every recommended answer (Q1 to Q30). Words: subproject for the user, nest in commands and code (Q18). crates/paw-core/src/session/folder.rs; docs/reference/project-files.md, docs/reference/subprojects.md; the code of TASK-7.14 (the project text that a nest becomes, the other way).

Depends on: TASK-7.14 (both convert between a project folder and a nest; do the conversion once).
Do not touch: projdiff and nest kinds.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test: :import of a folder plays it; the first edit says once that it is now the song's own copy, and origin keeps the path
- [x] #2 Test with real keys: :nest.own makes the copy now; u puts the reference back
- [x] #3 Test: :e song/nests/Bridge opens the song inside Bridge
- [x] #4 subprojects.md and project-files.md say it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a50cca60877f5fa84 (on top of 7.14's branch worktree-agent-a0332da24e5271487): 59d71324 (the work), 8cc1efaf (merge of main 8e91e5b0). :import <project folder> makes a subproject that refers to the folder (Nest::source) on its own row with one block; model/nest/adopt.rs (inverse of standalone.rs; ids from the nest id on, stable across opens; nests inside come along with the same source; follows the song tempo with the folder's kept, own meter). Save writes only nests/<name>/nest.toml {id,name,source}; read re-reads the folder (folder/nests.rs), a missing folder opens with a message. First edit owns the whole reference in the same step and emits nest.copied once (Document::own_edited_nests); :nest.own = paw.api.nest_own, one undo step. :e <song>/nests/<name> opens the song and enters the subproject (paw.nest.open, paw.nest.song_of). Docs: subprojects.md (new section), project-files.md, events.md. Needs build then tools/apidoc.lua (api.d.tl and kernel.tl hand-written as apidoc writes them; paw.lua, api.md need regen). Tests after build: suite.sh only ':import' ':nest.own' 'subproject' (and 7.14's); cargo nextest run -p paw-core -E 'test(adopt) | test(nests) | test(document)'.

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
