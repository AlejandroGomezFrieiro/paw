---
id: TASK-123
title: >-
  Vertical zoom: Ctrl +/- for track height, piano roll key height and lane
  height
status: Done
assignee: []
created_date: '2026-11-22T18:29:00Z'
updated_date: '2026-11-22T21:52:00Z'
labels:
  - ux
  - zoom
  - view
milestone: m-4
dependencies: []
priority: high
ordinal: 135000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-11-22: zooming works only in time (zi, zo). There is no way to zoom vertically: track height, the piano roll's key height, lanes. 'Ctrl +/- should help with zooming.' Today only <C-w>+ and <C-w>- change track height, and only when the arrange view is alone in its tab.

Design (mine; check terminal support first):
- <C-=> (and <C-+>) zooms in vertically, <C-->  zooms out, <C-0> goes back to automatic (fit). They act on the view under the cursor: arrange = track height (all tracks; with a count or on a selection, those tracks only), piano roll = rows per key (1, 2, 3; zooming out below 1 row per key shows two keys per row with half blocks if that reads well, else stops at 1), automation and lane rows = lane height, notation = staff size if it has one.
- Many terminals send nothing for Ctrl+= or Ctrl+-, unless the kitty keyboard protocol or modifyOtherKeys is on; find what paw-tui enables (crossterm keyboard enhancement flags). If the keys can't arrive, add z+ z- z= as the same actions everywhere (and say in K and the hint which works where). The window (paw-gui) gets Ctrl+wheel for time zoom and Ctrl+Shift+wheel (or Alt+wheel) for vertical zoom, the same actions.
- Each zoom says what it did ('track height 5', 'piano roll: 2 rows per key'); it is view state, not an undo step; saved in screen.json per window like the time zoom.
- <C-w>+ and <C-w>- go back to resizing windows only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Real-keys test: in the arrange view <C-=> makes tracks taller and <C-0> fits them again; on a selection of tracks only those change
- [ ] #2 Real-keys test: in the piano roll <C-=> gives 2 rows per key, notes drawn over both rows, and the cursor moves by key, not by row
- [ ] #3 Terminal support checked and written down: what paw-tui asks the terminal for, and the z+ z- z= fallback keys work everywhere (test)
- [ ] #4 paw-gui: Ctrl+wheel zooms time, the vertical wheel zoom changes the same option; scene_parity and paw-gui tests pass
- [ ] #5 The zoom is kept per window in screen.json and is no undo step (test)
- [ ] #6 keys.md, arrange-view.md, piano-roll.md describe the keys; Vale 0
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-adb4f117cedb6dfb8: commit 553521ba, then merges of main (601b0364, d0318e8e). paw/vzoom.tl: per-window vertical zoom (win.vzoom: track_rows, tracks {track, rows}, lane_rows, key_rows), saved in screen.json next to the folds; never an undo step; a split copies it. Keys <C-=>/<C-+> <C--> <C-0> and z+ z- z= (n and x modes), :vzoom 1|-1|fit; a selection or a count changes only those tracks; with the cursor on an automation lane, the lane height changes. Piano roll: 1 to 3 rows per key, and the cursor moves by key. <C-w>+ - = resize windows only. Terminal: paw-tui asks for no keyboard protocol (no kitty flags, no modifyOtherKeys), so most terminals do not send Ctrl = - 0; this is written in crates/paw-tui/src/terminal.rs and the docs. paw-gui: Ctrl = - 0 go to the kernel mappings, Ctrl up/down run :vzoom, Ctrl+wheel zooms time, Alt+wheel zooms vertically. Not done: half-row keys (two keys per row) and the notation staff size (no notation zoomer; paw.vzoom.define is the hook). Tests: tests/vzoom.lua (4), tests/windows.lua and tests/flow.lua updated. The orchestrator must run at the merge: cargo test -p paw-gui -p paw-scene -p paw-tui, apidoc check, full suite. Seen on main too: tuimouse 'dragging a note's last cell resizes it' fails when it runs after the other 'resize' tests (only resize), not alone.

Merged to main (batch 2, 2026-11-22): dev build, full suite with plugins passed in one process; nextest paw-core/paw-scene/paw-tui passed. -j 2 order failures moved to TASK-144.
<!-- SECTION:NOTES:END -->
