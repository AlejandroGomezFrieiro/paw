---
id: TASK-190
title: >-
  One cache key for 'the project or the events changed', and the first scope
  keys that got slower after TASK-184
status: Done
assignee: []
created_date: '2026-11-23T00:59:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-3
dependencies: []
priority: medium
ordinal: 202000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-184 (2026-11-23, branch worktree-agent-a64414700dab9162b). (1) groups.tl, scope.tl and ui.tl each build their own key from the project's edit count and the events sent; make one helper (for example paw.stamp()) and use it in all three, after TASK-130 (ui.tl) is on main. (2) In the one-shot scope scenario, znn (22 -> 40 ms), ]z (30 -> 68 ms) and znag (26 -> 40 ms) were slower with TASK-184, before the first frame; in the repeat scenario both branches cost the same. Cause not found (a GC pass is a guess). Find it with jit.profile or a GC count on those keys; measured under external load, with spread.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One helper gives the key, and the three caches use it
- [ ] #2 The one-shot cost of znn, ]z and znag is explained, and fixed if the branch caused it, with numbers in bench/RESULTS.md
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a6c3035f1cd3359a6: c9785e73 (paw.events.stamp, used by groups.tl, scope.tl, ui.tl frame_stamp; test in tests/hooks.lua; lua-views.md and api.md), ffdbfd7f (bench: drive.py scope gives gc_cycles, lua_kb, per-key --luaprof, --collect; bench/RESULTS.md section), e7f3034c (merge main b48920a4). AC2: the one-shot cost of znn, ]z, znag with TASK-184 is the incremental GC of LuaJIT moving its steps onto those keys (collector samples 73/52/83 vs 0/3/0 over 5 runs; :%quantize, u, piano roll get them before). The whole scenario costs the same (868 vs 866 ms). With a full GC before each key the medians differ less than the spread. No fix needed. The larger first-time cost of every key is the trace compiler (about 45 percent of samples): a possible new ticket.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
