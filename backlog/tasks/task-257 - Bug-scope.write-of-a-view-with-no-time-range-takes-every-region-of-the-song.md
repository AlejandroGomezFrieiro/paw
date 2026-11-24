---
id: TASK-257
title: >-
  Subprojects: :scope.write! keeps the song's regions, groups and routing; a
  window in a subproject keeps its own time (split scroll, region drag)
status: Done
assignee: []
created_date: '2026-11-23T07:21:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - bug
  - nest
milestone: m-2
dependencies:
  - TASK-226
priority: high
ordinal: 321000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the scopes UX design (TASK-233; screens in scratchpad/ux/v2.txt, shots O and P). :narrow Keys, then :scope.write! Keys2, says '6 markers and regions inside it', and the song has no region row afterwards. A view with no time range must take no markers or regions from the song (or, if the design says so, copy them and keep the song's).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 After :scope.write! of a group view with no time range, the song keeps all its markers and regions (test with real keys)
- [x] #2 The message names what moved into the subproject truthfully
- [x] #3 (TASK-265) :scope.write! of a group view keeps the group and puts the return row in it, so no route changes; when a route must change the message names it; a view over several buses gives one row to the master and names the buses, and a 'stems' word keeps them; subprojects.md says so
- [x] #4 (TASK-258) A golden screen test with real keys: a split, one window in a subproject, moving in the other window leaves the subproject window inside its bars
- [x] #5 (TASK-259) A drag of a region inside a subproject moves it to the song beat under the mouse (test with mouse events)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a99d806b0f5cfb26b (commits ddce0655, 7e74acfb). Rust: session/save.rs (whole_tracks: a track moves in whole only when all that plays into it moves; a group or bus the song still uses stays; the return row plays into the tracks' bus and goes into its group; several buses: row to master, Saved.buses, row meta nest_buses), api/tracks.rs doc. Lua: nest.tl (no markers moved for a view with no time; new message 'made the subproject ⧉X from ...'; route words; ':scope.write! Name stems'; nest.outputs stems routes each stem to its bus), scope.tl (paw.scope.cursor_beat), views/arrange.tl (follow and cursor drawing in the window's own time), views/arrange_mouse.tl (marker drag through the window's time). Docs: subprojects.md. Needs the Rust build: the routing tests in tests/nest.lua and the golden write_keeps_the_group must be run (and that golden blessed) after the orchestrator builds.

Merged to main in batch 16 (cd367da1); full suite and checks passed after three merge fixes.
<!-- SECTION:NOTES:END -->
