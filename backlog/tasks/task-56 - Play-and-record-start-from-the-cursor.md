---
id: TASK-56
title: Play and record start from the cursor
status: Done
assignee: []
created_date: '2026-11-22T04:39:00Z'
updated_date: '2026-11-22T05:36:00Z'
labels:
  - transport
  - ux
milestone: m-4
dependencies: []
priority: high
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-22: <Space><Space> playing from the playhead, independent of the cursor, feels strange: if the cursor is 200 bars ahead and the playhead is at the start, play/record should start from the cursor. Today: <Space><Space> plays from the playhead; Shift-Enter plays from the cursor; R records from the cursor (from the playhead while playing); gs/gp move the playhead; gP moves the cursor to the playhead. Do: when stopped, play starts at the cursor (the playhead follows the cursor while stopped); decide and document what stop does (playhead stays where it stopped vs returns to where play started, REAPER-style option) and whether the cursor follows the playhead after stop (recommend: cursor never moves by itself); an option (e.g. play_from = cursor|playhead, default cursor) for the old way; while playing, keys behave as now. Keep Shift-Enter coherent (maybe becomes play from the playhead, or goes). Update keys.md, arrange-view.md, the tutorial/tutor if they say where play starts, and tests with real keys (200 bars ahead: <Space><Space> starts there).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-aea28d7cdb5822dae, commit 266c58b6. <Space><Space>/R play from the cursor of the focused view (play_beat), playhead pinned by gs/gp/ruler; play_from=playhead is the old way; <S-CR> plays from the playhead.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged: play/record start from the cursor when stopped (play_from=cursor default); placed playhead (gs/gp/ruler click) kept until the cursor moves; <S-CR> plays from the other point; play_from=playhead is the old way.
<!-- SECTION:FINAL_SUMMARY:END -->
