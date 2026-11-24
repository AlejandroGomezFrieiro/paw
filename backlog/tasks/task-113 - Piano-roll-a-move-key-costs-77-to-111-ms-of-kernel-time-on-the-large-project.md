---
id: TASK-113
title: 'Piano roll: a move key costs 77 to 111 ms of kernel time on the large project'
status: Done
assignee: []
created_date: '2026-11-22T13:02:00Z'
updated_date: '2026-11-22T18:59:00Z'
labels:
  - performance
milestone: m-3
dependencies: []
priority: high
ordinal: 116000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-79 (paw.opt.budget_ms = 5, bench/profile/run.sh keys on project.lua, measured under external load, load average 14 to 94).

In the piano roll, `j` costs 77 ms of kernel processor time (load 14) and 101 to 111 ms (load 70 to 94), median of 5 presses. In the arrange view, `j` costs 7 ms (load 14). The budget check names 'drawing the screen' (7 times for 5 presses, 22 to 33 ms of wall time each) and 'drawing what moves' (5 to 17 times, 5 to 13 ms). The first frame of the piano roll (Enter on a clip) takes 370 to 540 ms of wall time under load 70 to 94.

Goal: a move key in the piano roll costs no more than a move key in the arrange view. Find the cost with bench/profile/run.sh repeat --keys '\r,j,k' --luaprof, and fix the largest parts.

Read first: bench/RESULTS.md (2026-11-22, TASK-79), runtime/lua/paw/views/ (the piano roll), bench/profile.md.
Do not touch: the arrange drawing (TASK-88).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 bench/profile/run.sh keys: 'j in roll' kernel time within 2x of 'j' in the arrange view, 5 runs, median and spread, measured under external load
- [ ] #2 With budget_ms = 5, 'j in roll' writes no slow warning for 'drawing the screen' at a load average under 20
- [x] #3 The tests of the piano roll pass unchanged
- [x] #4 A live frame keeps each live part whose bound value (playhead, meter) did not change and draws only the parts that changed; the cells are the same as a frame drawn whole (tests/frames.lua)
- [x] #5 The status line in a live frame is drawn again only when a component that moves without a whole frame (clock, transport, cpu, midi, render, take) changes; a component of the user with no key is drawn on each live frame as before (test)
- [x] #6 docs/reference/status-line.md names the new component field and which built-in components move by themselves; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a4e2eb80ccb38a310. Commits: 6cb39f6a (stamps of live parts: grid_live_keep, grid_live_still, Role.stamp, status line still/moves, transport_playhead, engine_load, only_live), c54a30ea and 21391dfc (a 20 fps rule for falling meters, then taken out on the owner's word; kept: a played note keeps frames until its meters are at rest), 546731b6 (projdiff test: a free clip id), merges of main 6d383c00, c50d7ef1, 88b53a7d and the last one. j in roll, 5 presses a run, 5 pairs in turns against main da45a4a0, load 14 to 23, measured under external load: main 53.1 ms (52.5 to 86.4), branch 38.1 ms (35.9 to 48.5). AC1 and AC2 stay open, accepted by the owner: the remaining cost is the falling meters at the full paw.opt.fps (paw.opt.fps is an upper limit only; a frame comes only when a cell it shows changed), and the whole frame after the key draws the arrange view above the roll (55 % of that frame), which 'drawing the screen' still names. With a 20 fps rule j in roll was 19.0 ms (18.1 to 30.9) against 51.6; the owner did not want it. See bench/RESULTS.md.
<!-- SECTION:NOTES:END -->
