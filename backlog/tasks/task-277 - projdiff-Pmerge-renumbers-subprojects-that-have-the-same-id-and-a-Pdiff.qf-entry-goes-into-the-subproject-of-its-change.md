---
id: TASK-277
title: >-
  projdiff: :Pmerge renumbers subprojects that have the same id, and a :Pdiff.qf
  entry goes into the subproject of its change
status: Done
assignee: []
created_date: '2026-11-23T11:11:00Z'
updated_date: '2026-11-23T13:48:00Z'
labels:
  - projdiff
  - subprojects
milestone: m-5
dependencies: []
priority: medium
ordinal: 339000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-211 (its agent named these gaps; docs/reference/limits.md says both today).

- :Pmerge renumbers tracks, devices, clips and lanes that two sides gave the same id, but not subprojects. When both sides add a subproject, or a track inside a subproject, with the same id, the merged project can fail to load. Renumber subprojects and the tracks inside them as the merge does for the song's tracks, with what points at them (blocks, return rows, nests/<name> folders).
- Enter in the window of :Pdiff goes into the subproject of a change. A quickfix entry of :Pdiff.qf only puts the cursor on the change in the scope that the window shows. Make the quickfix entry go into the subproject as Enter does.

Read first: extensions/projdiff (merge.lua, view.lua, diff.lua, README.md); the TASK-211 commit 980d1237; docs/reference/limits.md (the projdiff part); runtime/lua/paw/nest.tl (go inside a subproject).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: both sides add a subproject with the same id; after :Pmerge and the choices, the project saves, opens again and has both subprojects
- [ ] #2 Test: both sides add a track with the same id inside one subproject; the merged project opens and has both tracks
- [ ] #3 Test with real keys: :Pdiff.qf, then a jump to an entry of a change inside a subproject, puts the window in that subproject's scope with the cursor on the changed track
- [ ] #4 limits.md and the README of projdiff are true; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a1255df3718e68ec8, commit a0009526 (on main 7228146b). merge.lua renumbers subprojects (and their masters, tracks, devices, clips, the blocks and return rows that place them) when both sides used one id; holder rule and remapped comparison in a fixpoint. Core: paw.nest.show(id) (way into a subproject, moved from projdiff view), paw.qf.go enters the subproject of an entry (entry.nest or the track's), arrange locator rows follow the subproject of the window (before: a jump to a nest track fell on the first track; the old Enter test passed by chance). Tests: 3 new in extensions/projdiff/tests.lua, 1 changed. limits.md lines removed; README, quickfix.md, lua-addresses.md follow. Vale 0.

Landed on main in batch 17 (deb79a0f), with the merge fixes of 2026-11-23 (clock rounding, export leader domain, goldens, MCP render_stems).
<!-- SECTION:NOTES:END -->
