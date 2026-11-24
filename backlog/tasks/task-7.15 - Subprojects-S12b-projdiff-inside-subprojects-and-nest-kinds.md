---
id: TASK-7.15
title: 'Subprojects S12b: projdiff shows the changes inside subprojects'
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-23T07:01:00Z'
labels:
  - nest
  - subprojects
  - extensions
milestone: m-2
dependencies:
  - TASK-7.3
  - TASK-7.6
parent_task_id: TASK-7
priority: medium
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the versions extension (projdiff) sees changes inside subprojects. Nest kinds moved to TASK-7.17 on 2026-11-23.

What to build (nest.md 4.10): extensions/projdiff recurses into nests/: <Space>gd shows a change inside a subproject under its name, also for a subproject inside a subproject.

Read first: Design: backlog/docs/designs/nest.md, section 4.10; the owner accepted every recommended answer (Q1 to Q30). Words: subproject for the user, nest in commands and code (Q18). extensions/projdiff (init.lua, git.lua, tests.lua) and its README; docs/reference/project-files.md (the nests/ folders).

Do not touch: the playback; nest kinds (TASK-7.17).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test (extensions/projdiff/tests.lua): an edit inside a subproject shows under its name in the diff
- [x] #2 Test: an edit inside a subproject of a subproject shows under both names
- [x] #3 The README of projdiff says it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a75e8062e2b7866c6, commit b74230d2 (main e46ecc13 is merged, no new commits on main). extensions/projdiff/lua/projdiff/diff.lua groups the tracks of each subproject under a heading 'subproject <id> "<name>"' (fields, meta, tracks, master as 'master'); a subproject placed by another subproject goes under it (the song wins when both place it; unknown parent or a loop goes to the top). Tests: two in extensions/projdiff/tests.lua (<Space>gd with real keys; two levels deep with the quickfix trail). README 'What a diff names' and docs/reference/limits.md (the merge does not renumber subprojects) changed. Vale 0. Not done: merge.lua and text.lua (git textconv) have no special subproject handling; Enter on a change inside a subproject was not checked to enter the subproject's scope; :Pdiff on a folder project is not supported by projdiff (it reads one JSON file).

PO 2026-11-23: the three things not done have tickets: TASK-210 (projdiff reads a project folder: file, git revision, snapshot; it is broken for every folder project now), TASK-211 (textconv and :Pmerge know subprojects), TASK-212 (Enter on a change inside a subproject).

PO 2026-11-23 check of main: extensions/projdiff/tests.lua has the two subproject tests (one level with real keys, two levels); the README section 'What a diff names' says it; Vale 0 on the README and limits.md. All criteria met.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged in 89d0e8db. projdiff shows a change inside a subproject under the subproject's name, also two levels deep. Follow-ups: TASK-210, TASK-211, TASK-212.
<!-- SECTION:FINAL_SUMMARY:END -->
