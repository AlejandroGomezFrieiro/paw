---
id: TASK-102
title: 'Recording: a Take module, and stop never waits on the kernel thread'
status: Done
assignee: []
created_date: '2026-11-22T10:39:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels:
  - performance
  - rust
  - recording
milestone: m-10
dependencies: []
priority: medium
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the record of takes is one module with a Take type, and the stop of a take never blocks the kernel thread. Finding F8 of the architecture review (backlog/docs/designs/architecture-review.md).

Today: the logic is in impl Session in crates/paw-core/src/session/transport.rs: start_take (106 lines), finish_take (123), add_recorded_audio (122), add_recorded_notes (122). Recorder (session.rs:136) holds only data. finish_take (transport.rs, lines 397 to 410) waits on the kernel thread for up to 2 s with sleep(1 ms) in a loop until the engine closes the take.

Change: a record module with Take (start, collect, close, make clips). The close is a state: the kernel sends SetTake(None) and returns; a kernel message from the engine finishes the take later, as stretch results do. One user action stays one undo step with one message.

Read first: the review, F8; session/transport.rs; session.rs (Recorder, Recording); crates/paw-engine/src/record.rs; docs/reference on recording; AGENTS.md rules 6 and 7.
Test: with real keys and --audio null: record, Space to stop, the clip is there, one undo removes it; the stop key returns at once.
Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No sleep loop on the kernel thread when a take stops
- [ ] #2 A test with real keys records, stops with Space, and finds the clip; one undo removes it
- [ ] #3 The take logic has Rust tests with the null backend
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a14841a73a9a9b213. Commits e30165cc (the change) and 50807ecd (merge of batch f5adec5e). session/recording.rs: Recorder, Take, TakeFile, Pass; close_take, poll_takes (from idle), takes_let_go (engine restart), finish_takes_now (project replace, drop). The scratch media folder comes from the session's Dirs (TASK-189). stop() sends Stop + Seek(position) and never waits. New typed event transport.recorded { take } (kernel.tl generated); transport_get().closing. The launcher makes the slot clip on transport.recorded. Tests: 5 Rust unit tests in session/recording.rs; Lua test 'the stop key ends a take at once' (record_mix.lua); T.stop()/T.until_recorded(). After the build: cargo test -p paw-core session::recording, cargo test -p paw-tui --test safety, full Lua suite.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
