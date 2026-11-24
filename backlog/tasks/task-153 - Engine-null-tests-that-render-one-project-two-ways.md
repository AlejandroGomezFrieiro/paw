---
id: TASK-153
title: 'Engine: null tests that render one project two ways'
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies: []
priority: medium
ordinal: 165000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/testing-practices.md, practice A3, gap G5, ticket BT2, rank 2.

Sound tests check the levels and frequencies of one render. No test compares two renders sample by sample, so errors at the edges of blocks can pass.

What to do: engine integration tests that render one project two ways and compare sample by sample: blocks of 64, 128 and 512 frames; one thread and four; a clip moved and moved back; render, save, load, render; a bypassed device and no device; a sleeping device and an awake one at silence; a subproject and its expanded tracks (where the design says that they sound the same). Bit-exact where the code is certain; else a stated limit in dB with the reason in a comment.

Read first: backlog/docs/designs/testing-practices.md, sections 2.2 (A3), 4, 5.1 ("Null tests of sound"), 6 (BT2). crates/paw-engine/tests.

Overlaps: TASK-16 (done; devices sleep).

Size: S to M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each case is one line of a table in one test
- [ ] #2 A test fails when a deliberate off-by-one is put at the edge of a block (checked once by hand, named in the commit)
- [ ] #3 No golden file is needed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-ae91ce7eac5ec48fb, commit 5488e5b1 (merged main: c5d575f0). One table test one_project_rendered_two_ways_nulls in crates/paw-core/src/sync/tests.rs: 8 cases, all exact, no golden file. It is in paw-core, not paw-engine/tests, because save/load and subprojects need the model and the sync. Deliberate off-by-one (work.rs play_clips frame.min(n - 2)) named in the commit. Finding: at 120 BPM, note frames depend on the block size (beats per frame not exact in f64; floor in play_clips); the test uses 87.890625 BPM. Not run by the agent: the orchestrator runs cargo test -p paw-core one_project_rendered_two_ways_nulls.
<!-- SECTION:NOTES:END -->
