---
id: TASK-150
title: 'Remote: a sync barrier and sequence numbers in place of quiet periods'
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies: []
priority: medium
ordinal: 162000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/test-suite-review.md, finding T8 (the remote part), ticket P7.

`crates/paw-tui/tests/remote.rs` checks absence with `quiet(&c, 400 ms)` (17 uses in the crates, also `paw-mcp/tests/protocol.rs`). Two sources of messages share one stream with no order, so a test had to skip "a state with only the levels".

What to do: a request `frontend.sync` that returns the sequence number of the last state sent, after it flushed all that was due. Each pushed state carries its sequence number. "Nothing is sent when nothing changed" becomes: sync, then sync again, and no state between the two. The levels go at a pace on the clock. Change each `quiet()` check to the barrier.

Read first: backlog/docs/designs/test-suite-review.md, sections 3.1 (rule 4), 3.2 (seam F, the remote part), 4 (T8), 5.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No quiet(Duration) in remote.rs and protocol.rs
- [ ] #2 An absence check is a sync, a sync again, and no state between the two
- [ ] #3 The protocol reference documents frontend.sync and the sequence number
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
frontend.sync barrier + seq on frontend.state. Branch worktree-agent-afbebd2ecd65a8f03, commits 239357b0, 45522e04 (merge main), fd3f5d17. kernel.rs settles the turn before frontend.sync; remote.tl answers the seq after it pushes what is due (scene.tl M.sync for scenes and live values); monitor.rs holds the listener lock while it queues frames. remote.rs has no quiet(Duration): pushed_by = sync, act, sync, events between. protocol.md documents it. Rust tests to run: cargo test -p paw-tui --test remote. Finding: on main, rapid back-to-back calls are handled in one kernel turn (the try_recv loop), so their events and undo step wait; not fixed here.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
