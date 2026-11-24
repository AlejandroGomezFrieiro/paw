---
id: TASK-124
title: 'Screen: keep the cells of a window whose stamp did not change'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-22T22:41:00Z'
labels:
  - architecture
  - lua-review
milestone: m-3
dependencies: []
priority: high
ordinal: 136000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ui.render_screen` draws every window on each frame. Add an optional `stamp(self, ctx)` to the contract `View`; keep the cells of each window rect with `buf:keep` under its stamp, and put them back when the stamp is the same. Adapters: the arrange view (its row cache), the piano roll, the mixer, the track list. Add `paw.opt.check_stamps` that draws anyway and fails on a difference.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L2 and its proposal P2.

Overlaps: TASK-113 (do them together), TASK-77.2, TASK-77.4.
Dependencies: none. Better with TASK-77.2 and TASK-77.4 (the stamps of the nodes).

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).

Note: TASK-113 (merged) already keeps the parts of a live frame that did not change. This ticket does the same for the whole frame after a key, per window.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 a move key in the piano roll does not call the `render` of the other windows (a test counts calls)
- [ ] #2 the kernel time of `j` in the piano roll on the bench project falls, measured with the spread against main
- [ ] #3 the view tests pass with `check_stamps` on
- [ ] #4 the reference page on views documents `stamp`
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-aea2569883c4acdeb. Commits: 9f25d4cf (the screen keeps the cells of a window whose stamp did not change: View.stamp, paw.events.emitted(), paw.opt.check_stamps, paw.ui.stamp_misses, adapters arrange/pianoroll/mixer, tests in tests/frames.lua, the suite runs with check_stamps on and fails a test with a miss, docs lua-views.md/options.md/about-scenes.md), c1b47bf4 (check around one pcall; bench/profile/drive.py passes PAW_RUNTIME; bench/RESULTS.md), fc1b9c7f, merges of main. A window without the keyboard is kept under its view's stamp plus a frame stamp (events sent, project edits, transport) plus place, background and winbar; its live parts (playhead, meters) are put back with the cells under them and the cells they drew, so a live frame after it is right (test). No track list view exists: the track column is part of the arrange view and its stamp. j then k in the roll on the bench project, 8 pairs, load 4 to 13, measured under external load: kernel time per round main 32.8 ms (25.9 to 40.6), branch 29.8 ms (22.7 to 33.8); frames drawing the screen for 5 ms or more in 60 keys: main 23 to 29, branch 5 to 9. Lua only, no Rust change. Not touched: paw-gui.

Merged to main (batch 3, 2026-11-23): dev build, nextest paw-core/engine/tui, full suite with plugins passed. At the merge: tests/suite.lua stamp check joined with TASK-121's runner; roll_context.tl's local paw renamed (strict tl check).
<!-- SECTION:NOTES:END -->
