---
id: TASK-163
title: >-
  Edits: Lua collector pauses at the end of a turn, and the key d (operator
  before its motion)
status: Done
assignee: []
created_date: '2026-11-22T21:29:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-3
dependencies:
  - TASK-164
priority: medium
ordinal: 175000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-116 (2026-11-22, branch worktree-agent-a4a363285a8ca1d8b). After the handler fixes, one slow-handler warning in 400 presses is left (7.2 ms at load 13.9): the time was in the Lua garbage collector (the heap shrank in that turn) or in paw.api.events_take (up to 4.6 ms, about 0.5 ms after u of dd). The key d (the operator before its motion) takes 7 to 10 ms. Tools: bench/profile/handlers.lua and drive.py --report (bench/profile.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 bench/RESULTS.md names where the time of the key d goes, and it is under 5 ms on the bench project (measured under external load, with spread)
- [ ] #2 The collector work after an edit is moved out of the key's turn (an idle step of the collector, or a budget check that does not count it), and the slow-handler warning does not name an event handler for collector time
- [ ] #3 events_take after u of dd is measured and its cost explained or reduced
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a32d695f3a9b169ae, commit 70ac3db2 (on b404646a; main merged, up to date). Key d: its cost was one whole frame (arrange render 74% of samples, trace compiler 57%). Now a key that only waits draws only the status and command lines; View:operator_shown asks for a whole frame. kernel.rs input() no longer sets dirty for keys (K.key asks), so the cmdline line-only frames now also work for terminal keys. d over the socket: 5.3-6.4 ms main, 1.4-1.6 ms branch (load 3.8-5.1). paw/collector.tl runs LuaJIT cycles as job collector between keys; no 'an event handler' warning from a cycle in the branch runs; some job slices 5-15 ms are single indivisible GC steps. events_take after u of dd: 35 events, 0.22 ms median both sides; the big calls in main were GC steps. Needs: orchestrator build, paw-core tests, full Lua suite. Details in bench/RESULTS.md.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
