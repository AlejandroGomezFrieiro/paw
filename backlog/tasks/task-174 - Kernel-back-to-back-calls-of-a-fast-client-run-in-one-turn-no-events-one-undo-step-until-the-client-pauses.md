---
id: TASK-174
title: >-
  Kernel: back-to-back calls of a fast client run in one turn (no events, one
  undo step) until the client pauses
status: Done
assignee: []
created_date: '2026-11-22T22:49:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-3
dependencies: []
priority: high
ordinal: 186000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-150 (2026-11-23). With the main binary, an add_track then five evals over the socket with no pause: the project revision did not change and no events came until the client paused; with 0.3 s pauses they came at once. Likely the inner try_recv loop in crates/paw-core/src/kernel.rs takes a fast client's calls in one turn and never ends it, so events and pushes are held back and the undo steps merge into one (rule 6: one action, one undo step). TASK-150 (branch worktree-agent-afbebd2ecd65a8f03) adds settle() before frontend.sync; build on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each request from a client ends its own turn: its events go out and its undo step closes before the next request runs, by a test over the socket with back-to-back calls and no pause
- [ ] #2 Keys from the terminal keep their batching where a key is one action
- [ ] #3 No test waits for a time
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause: Kernel::run handled one message, then took each message already in the channel (try_recv loop) and called settle once after all of them. A client that sends its next request as soon as it reads a reply put it into the channel before the loop ended, so its requests shared one turn: events held back, one undo step, until the client paused. Fix: kernel.rs Kernel::request (the Lua requests of a connection: eval, cmd, paw.remote methods) settles in the instance's seat before the reply; events are queued before the reply. Terminal keys (KernelMsg::Input, ui.input) keep their batching; frontend.sync still settles first for them. Test: crates/paw-tui/tests/remote.rs each_request_is_a_turn_of_its_own (no time, no barrier; fails on old code because the event is queued after the reply). Bench: bench/edit.lua turn <tracks>, RESULTS.md 2026-11-23: an empty turn ~0.005 ms, an edited turn 0.05 ms (10 tracks) to 0.46-0.64 ms (500 tracks), wall time under load 11-13. Branch worktree-agent-aaa60f25c11d67c8a (includes TASK-150 branch), commit 7caf2930. Orchestrator: cargo nextest run -p paw-tui -E 'binary(remote)', cargo nextest run -p paw-mcp (protocol: undo labels), suite.sh only remote.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
