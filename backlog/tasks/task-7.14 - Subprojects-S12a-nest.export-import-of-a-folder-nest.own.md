---
id: TASK-7.14
title: >-
  Subprojects S12a: :nest.export and :scope.write <folder> write a standalone
  project
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-23T08:31:00Z'
labels:
  - nest
  - subprojects
  - files
milestone: m-2
dependencies:
  - TASK-7.6
parent_task_id: TASK-7
priority: high
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: a subproject, or a view, goes out of the song as a project of its own. Nothing in the song changes.

User-visible behavior (nest.md 3.6, 3.7 table, 4.3; Q10):
- :nest.export <folder> writes a standalone project: project.toml from nest.toml, the follow maps resolved from the first block, its media collected by hash.
- :scope.write <folder> (a path) writes a view as a standalone project folder in the same way (a copy, nothing moves). :scope.write <name> (no slash) keeps its meaning from TASK-7.9: save a view as a subproject in the song. Commit e6ad5cd7 already refuses a name with a slash in the name form; this ticket gives the path form its meaning.

Read first: Design: backlog/docs/designs/nest.md, sections 3.6, 4.3; the owner accepted every recommended answer (Q1 to Q30). Words: subproject for the user, nest in commands and code (Q18). crates/paw-core/src/session/folder.rs, the media collect code (:collect, crates/paw-core/src/media), docs/reference/project-files.md, docs/reference/media.md, docs/reference/subprojects.md.

The other half (:import of a folder, :nest.own, :e song/nests/<name>) is TASK-7.16.
Do not touch: projdiff and nest kinds (TASK-7.15, TASK-7.17).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test: an exported subproject opens alone and renders the same as its block in the song
- [x] #2 Test: :scope.write <folder> writes a project that opens alone; the song does not change
- [x] #3 Test: :scope.write <name> still saves a view as a subproject in the song; the two forms are told apart by the slash
- [x] #4 subprojects.md and project-files.md say it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a0332da24e5271487: d2fd310b (the work) and 796dde21 (merge of main 7f02e829). :nest.export <folder> and :scope.write <folder> (a path has a slash) write a project folder of their own: model/nest/standalone.rs makes the project (subproject: its tracks, master as master, tempo and meter of the first block when it follows; view: copies cut to the time, routes out cut and told), session/export.rs writes it to a new or empty folder with media copied by hash. New API paw.api.nest_export, paw.api.scope_export; paw.nest.export, paw.nest.write. Docs: subprojects.md (new section), project-files.md. Needs a build: generated declarations were made with stand-ins for the two kernel functions; run apidoc after the build. Tests to run after the build: suite.sh only 'scope.write' and ':nest.export' and 'nest' ; cargo nextest run -p paw-core -E 'test(standalone) | test(nests) | test(save)'.

PO 2026-11-23: the owner approved the export design. TASK-222.7 (E7) later replaces :nest.export and :scope.write <folder> with :export project <folder>/; it depends on this ticket.

Merged to main in batch 14 (23350734); full suite and flake-equivalent checks passed.
<!-- SECTION:NOTES:END -->
