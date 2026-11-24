---
id: TASK-116
title: 'Edits: the event handlers after x, dd and u take 5 to 12 ms together'
status: Done
assignee: []
created_date: '2026-11-22T13:03:00Z'
updated_date: '2026-11-22T23:53:00Z'
labels:
  - performance
milestone: m-3
dependencies: []
priority: medium
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-79 (paw.opt.budget_ms = 5, bench/profile/run.sh keys on project.lua, measured under external load, load average 70 to 94).

After x, dd and u, the budget check names 'an event handler' (the guard of K.settle in runtime/lua/paw/init.lua, 5 to 9 ms), 'a handler of `clip.added`' (11.5 ms, after u) and 'the key d' (7 to 10 ms, the operator before its motion). No single handler is over the budget for 'an event handler': the sum of many handlers is. The kernel time of dd is 82 ms and of its u 109 ms (load 14, one press each); the chord reading in slices (the job harmony) is part of it.

Goal: name the handlers that run after an edit and their cost (paw.limit.timed gives each its name already), then make the large ones cheaper or move their work to paw.slices.

Read first: bench/RESULTS.md (2026-11-22, TASK-79), runtime/lua/paw/init.lua (settle), runtime/lua/paw/events.tl, TASK-13.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A list of the handlers of clip.added, clip.removed and changed with their cost on the large project, in bench/RESULTS.md
- [ ] #2 With budget_ms = 5, x, dd and u write no slow warning for an event handler at a load average under 20
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a4a363285a8ca1d8b, commit 7d3aefcd (main fd0e1f0b merged, up to date). Lua/Teal only, no Rust. derived.tl: a mark only notes the source; entries become stale at the next read (get/want/fresh) or in the next slice of the job derived (one mark of the track list made 4710 entries stale, 0.8 ms). freeze.lua, groups.tl, address.tl: no failed reads of a removed track or device (a failed read costs 65-107 us, mlua traceback). transport.lua take handlers: read the armed field of the track before the whole clip. bench/profile/handlers.lua times each handler; drive.py --report and PAW_RUNTIME passthrough; bench/RESULTS.md has the list (AC1). AC2: settle sum per press x 1.29->0.88 ms, dd 2.41->0.54, u after dd 2.92->1.62; A/B 10 runs each at load 4.5-14.4: main named a slow event handler in 6 runs (9 times), branch in 1 run (once, 7.2 ms at load 13.9; the remaining spikes are the Lua collector, not a handler). 'the key d' (operator) stays open.

Merged to main (batch 4, 2026-11-23): dev build, apidoc regenerated, nextest paw-core/engine/tui/mcp (400) and the full suite with plugins passed. At the merge: vzoom.tl's Paw record names the keymap (TASK-125 took it out of partial.Paw).
<!-- SECTION:NOTES:END -->
