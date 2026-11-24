---
id: TASK-261
title: >-
  UX-1 to UX-3: the window bar in the ruler's two left cells, the end of a
  scope, and a subproject's rows under its return row
status: Done
assignee: []
created_date: '2026-11-23T07:52:00Z'
updated_date: '2026-11-23T13:48:00Z'
labels:
  - ux
  - nest
milestone: m-15
dependencies:
  - TASK-226
priority: high
ordinal: 325000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/scopes-ux.md (approved by the owner 2026-11-23, all recommendations). Each change gets T.expect_screen golden tests at 100x30 with the real keys; put a before/after screen in the report.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The two left cells show the scope path and the cursor (scope bar and @song bar) per window; the › mark in the track column is gone; each split says where it is
- [ ] #2 (TASK-262) A scope ends with ┃ on the ruler and every row, nothing drawn after it, 'end of <scope> · zw: the song' on the ruler; song bars read @9 in the status line, K and messages (the (9.1) form goes)
- [ ] #3 (TASK-263) za on a return row shows ▾⧉ Name ×N, the ┆ guide on its rows, the block frame, no song numbers on its rows, blank outside its blocks, and a closing line 'end of ⧉Name'; the message says an edit changes all places
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a45bf70444a33537b: commit 82084e4e (UX-1 to UX-3), merge of main 5c0ce46f. Window bar in the ruler's two left cells (path + cur place @song), the scope sign in the track column removed; hard end ┃ with nothing after it and 'end of <scope> · zw|zW: the song'; a row of song bars @N under the scope's bars; @9 form in status line, K and messages; a region that covers the scope leaves the lane. za on a return row: ▾⧉ Name ×N, block frame, ┆ guide, no song numbers, clips only in the blocks, closing line 'end of ⧉Name', message names the places. Not done: the light TrackHeaderNest header, the 'l' end-of-scope message (not in the AC). No Rust changed; paw-scene untouched.

Merged batch 17 (09df69e0) into the branch: commit 5d4ffd4c. All four features kept; golden screens blessed again; layers-allowed paw.cursor paw.keymap 2 (the stop hook of batch 17).

Landed on main in batch 17 (deb79a0f), with the merge fixes of 2026-11-23 (clock rounding, export leader domain, goldens, MCP render_stems).
<!-- SECTION:NOTES:END -->
