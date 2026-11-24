---
id: TASK-192
title: ':%quantize on about 6,400 notes still takes about 135 ms of kernel time'
status: Done
assignee: []
created_date: '2026-11-23T01:26:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-3
dependencies: []
priority: medium
ordinal: 204000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-183 (2026-11-23, branch worktree-agent-a3515cae585801fdd): u now meets 100 ms, :%quantize 1/4 does not (135 ms, 85 to 190, measured under external load). Its profile: two frames of 20 to 35 ms (part is trackcolumn.tree_of, which TASK-184 removes: measure again after 184 is on main); command completion sorts commands.list after each character and the preview parses the range (about 10 ms); ex.items gets each note from the kernel as a table (about 9 ms) and sorts the items (about 5 ms); and the job 'derived' went over 10 ms in 2 of 25 keys, probably a GC step in a slice (not shown). Start after TASK-183 and 184 are on main.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 :%quantize 1/4 in the scope scenario is under 100 ms of kernel time, or each part left is named with numbers in bench/RESULTS.md
- [ ] #2 Any test counts work, never time
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a84f3d532290a1ac8 (on main b48920a4). Commits a12e9554 (code, tests, drive.py scope-keys), a469d3ff (RESULTS.md). :quantize uses new paw.notes.snap (no copy per note); ex.items merge sort in Lua (table.sort comparator from C is not compiled); commands.list keeps its sorted list until define/alias/put. Allocation per :%quantize 15.3 to 11.4 MB; GC samples 19.4 to 11.5 ms/key; command 48 to 32 ms of samples. Whole-key kernel time: no measurable difference (one series 140 to 109, the other 124 to 132 medians; spread 76 to 233; load 2.2 to 3.1). AC1 not met under 100 ms: parts left named in bench/RESULTS.md (chord reading 46, command 32, arrange frame 27, typing and events 27 ms). AC2: no timing tests; new tests check item order, snap against quantize, completion after commands change.

Orchestrator 2026-11-23: closed. Allocation 15.3 -> 11.4 MB per key, command 48 -> 32 ms of samples; the whole key shows no measurable change and is still over 100 ms. The parts left are TASK-198 (bulk note call), TASK-199 (incremental chord reading), the arrange frame (after TASK-127's port) and TASK-195 (trace compiler).

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
