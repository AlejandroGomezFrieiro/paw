---
id: TASK-264
title: >-
  UX-4, UX-7 to UX-9: K as a float with the new words, track_height=auto from 1
  to 3, the return row where o puts a track, and the words and docs of folds,
  scopes and subprojects
status: Done
assignee: []
created_date: '2026-11-23T07:52:00Z'
updated_date: '2026-11-23T13:48:00Z'
labels:
  - ux
  - nest
milestone: m-15
dependencies:
  - TASK-261
  - TASK-257
  - TASK-266
  - TASK-7.16
priority: medium
ordinal: 328000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/scopes-ux.md (approved by the owner 2026-11-23, all recommendations). Each change gets T.expect_screen golden tests at 100x30 with the real keys; put a before/after screen in the report.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 K opens a float at most 72 columns and half the window, under the cursor; K again goes into it; :info keeps the full page; K says subproject (not nest) and 'plays in N places'
- [ ] #2 (TASK-267) With track_height=auto a track takes 1 to 3 rows (today 3 to 4); golden screens of a 7-track song at 100x30 show all tracks
- [ ] #3 (TASK-268) The return row of :nest.new and :import goes in the cursor's group, as o does
- [ ] #4 (TASK-269) about-scopes.md, narrowing.md, subprojects.md, keys.md, the picker and the tutor use the design's marks and words; Vale 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch worktree-agent-a456c58a5ca8619a7, commits ee8f5312 (the work), 24704e85 (merge main), 8371a302 (main's new golden screens at the new height, caret in lua-views.md). K is a float under the cursor (paw.ui.hover, at most 72 columns and half the window high); the next key closes it; K again moves the keys into it as a page; :info keeps the page; :describe is the command of K. K on a block: subproject, tracks, plays in N places: @9 (here). Keys lines on fold, scope, block. Scope bars 'song @17-24'. Picker: subproject ⧉Name. track_height auto 1 to 3. :nest.new, :import and o/O put the new row into the cursor's group (paw.groups.home). Docs: keys, arrange-view, window, options, narrowing, subprojects, project-files, lua-views, the how-to on a section in another meter, tutor lesson 14 and course, api.md, lua-testing skill (T.hover_text). Golden screens at today's state of TASK-261/266: re-bless after they merge.

Landed on main in batch 17 (deb79a0f), with the merge fixes of 2026-11-23 (clock rounding, export leader domain, goldens, MCP render_stems).
<!-- SECTION:NOTES:END -->
