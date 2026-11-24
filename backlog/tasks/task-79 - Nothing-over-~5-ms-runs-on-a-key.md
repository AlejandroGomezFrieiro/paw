---
id: TASK-79
title: Nothing over ~5 ms runs on a key
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-22T14:48:00Z'
labels:
  - performance
milestone: m-3
dependencies:
  - TASK-14
priority: high
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: make rule 7 of AGENTS.md ("a key stays well under 100 ms") a check, not a hope. paw names each callback on the kernel thread that takes longer than a budget, and gives one helper to run long work in slices between keys. Then find and fix the callbacks that take too long on the large project.

User-visible behavior:
- `paw.opt.budget_ms` (default nil: off). When set (for example 5), each key handler, event listener, hook and timer callback that takes longer than the budget writes one warning to `:messages`: `slow: <name> 12 ms (budget 5 ms)`. Each name warns once per session. The tests and bench/profile set it.
- `paw.slices(name, step, opts)`: runs `step(ms)` again and again through `paw.defer` until it returns true. Each call gets at most `opts.ms` milliseconds (default 4). Keys that wait run between two slices. A new call with the same name stops the old job. `paw.slices.stop(name)` stops a job. `paw.slices.running()` lists the jobs, and the status line can show them.
- The chord reading (harmony.tl `work`) and the files picker walk (pick/sources.tl) use the helper. Their behavior does not change.

Read first:
- AGENTS.md rule 7. bench/RESULTS.md 2026-11-21 profile ("What is left").
- runtime/lua/paw/harmony.tl: `work`, `M.schedule`, `SLICE = 4` (near line 1040).
- runtime/lua/paw/pick/sources.tl (the walk in slices, near lines 498 and 1190) and runtime/lua/paw/pick.tl (`more`, near line 1448).
- runtime/lua/paw/init.lua: `paw.defer`, `paw.every`, `paw.timers`.
- runtime/lua/paw/keymap.lua (where a mapping runs), runtime/lua/paw/events.tl (`emit`), runtime/lua/paw/hooks.tl.
- bench/profile.md: `repeat --keys ... --luaprof`.
- docs/reference/lua-other.md ("Timers and state"), docs/reference/options.md.

Depends on: TASK-14 (merged). Measure on main after it: a full frame is still the largest cost (TASK-88).
Do not touch: the arrange drawing (TASK-88 works on it). Report offenders there to TASK-88 instead.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys (paw.keymap.feed): with budget_ms = 5, a mapping that busy-waits 20 ms writes one warning that names its keys and its time; a second press writes nothing more; a 1 ms mapping writes nothing
- [ ] #2 The same check names a slow timer callback and a slow event listener (one test)
- [ ] #3 Test: a 50 ms job in paw.slices runs in slices of at most the budget, and a key fed between two slices runs before the job ends
- [ ] #4 harmony.tl and the files walk use paw.slices; tests/harmony.lua and tests/files.lua pass unchanged
- [ ] #5 The check costs less than 1% of a key: two reads of a monotonic clock for each callback, measured with bench/profile repeat
- [ ] #6 bench/profile/run.sh keys on project.lua with budget_ms = 5: bench/RESULTS.md lists each offender with its time; each one is fixed in this branch or has a new ticket in m-3
- [ ] #7 docs/reference/lua-other.md documents paw.slices, docs/reference/options.md budget_ms; Vale reports 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a69e11c70a6e4afb0 (main merged at 9520bafb). Commits: b348e2ca budget (paw.opt.budget_ms, default 0 = off, in paw.limit: guard/named/call/timed; timers named by file:line; only the innermost slow callback warns; unhurried time not counted; paw.limit.slow) and paw.slices (run/stop/job/running); harmony (job harmony) and the files walk (job pick, more(ms)) use it. 5d933680 fixes: read.decode/key_path and the note merges pause (edit slices p90 8.6 -> 3.6 ms process time); text picker reads in slices (paw.grep.reader): first frame of <Space>fg 335 -> 35 ms. 158f2f95 pickers filter+draw at most every 100 ms while reading. 6b833d60 RESULTS + pickers.md more(ms). 7d072594 grid_fill doc comment back (TASK-88 merge broke the apidoc check). Check cost: 263 ns/callback on, 1 ns off, ~15 callbacks per key = ~4 us (0.06 % of j). New tickets: TASK-113 piano roll j 77-111 ms, TASK-114 help index slices, TASK-115 cmdline keys, TASK-116 edit event handlers. Arrange drawing offenders left to TASK-88. All measured under external load.
<!-- SECTION:NOTES:END -->
