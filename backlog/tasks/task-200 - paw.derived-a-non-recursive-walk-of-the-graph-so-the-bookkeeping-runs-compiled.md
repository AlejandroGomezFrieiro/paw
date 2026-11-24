---
id: TASK-200
title: >-
  paw.derived: a non-recursive walk of the graph, so the bookkeeping runs
  compiled
status: Done
assignee: []
created_date: '2026-11-23T03:10:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-3
dependencies: []
priority: medium
ordinal: 212000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-199 (2026-11-23): after :%quantize on Verse B, about half of the chord reading is paw.derived's bookkeeping for about 2,900 entries (went_stale, link, ensure, settle, near), and much of it runs in LuaJIT's interpreter because the graph walk is recursive. Make the walk iterative (an explicit stack or a topological order), and keep the 300-set random-edit test in agreement. Measure with TASK-199's probe (scratchpad t199/quant.lua: counts, allocation, bytecodes, profile) and drive.py scope-keys.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The walk of paw.derived has no recursion, and tests/derived.lua passes unchanged
- [ ] #2 Numbers in bench/RESULTS.md with their spread, measured under external load
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-ac63899b536f657d4 (on TASK-199's branch 39f9e77b). Commits 6bcf3a11 (derived.tl), and the bench/RESULTS.md entry after it. AC1: went_stale and the maybe-stale check of ensure walk with an explicit stack (ensure: a pooled stack per walk, because a make reads entries through ctx:get and starts a nested walk; that nesting through spec.make is user code, not the walk); push_over has a named overlaps predicate and no closure; went_stale calls schedule once per walk. tests/derived.lua unchanged, passes; derived:, harmony, chord, key, roll pass. AC2: no measurable gain (reading medians 18-25 ms both; whole key 126/147/148 vs 156/133/119 ms; load 3.8-14). LuaJIT call-unroll aborts in derived 22-37 -> 0. Finding: derived bookkeeping was already compiled before (581-603 native vs 7-13 interpreted samples); the cost is the count of entries touched (~2950 go stale; push_over checks ~18000 spans, 280 users x 64 tracks). Next gain: keep users of a track in span order.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
