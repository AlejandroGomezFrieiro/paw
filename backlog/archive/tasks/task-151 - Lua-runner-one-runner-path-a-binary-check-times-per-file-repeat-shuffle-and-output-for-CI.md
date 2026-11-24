---
id: TASK-151
title: >-
  Lua runner: one runner path, a binary check, times per file, repeat, shuffle
  and output for CI
status: To Do
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-121
priority: medium
ordinal: 163000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/test-suite-review.md, finding T9, ticket P8. backlog/docs/designs/testing-practices.md, practice L3, gaps G11 and G12, ticket BT9. The two tickets are merged here.

Today `crates/paw-tui/tests/suite.rs` and `tests/tools/suite.sh` are two runner paths with different folders. With `PAW_TEST_BIN`, an old binary with a new runtime prints Lua errors and the suite still says "all passed". The runner prints no time per file. Nothing repeats a test to find a flake.

What to do:
- `suite.rs` runs `tests/tools/suite.sh` (one runner).
- The runner compares a version stamp of the kernel API with the runtime, and fails at the start when they differ.
- The runner writes the wall time of each file to `target/test-scratch/times.txt` (information only, never a failure).
- `suite.sh repeat N only "<words>"`: stop at the first failure and print the run number.
- `suite.sh --shuffle <seed>`: print the seed; the same seed gives the same order.
- A TAP or JUnit file in `target/test-scratch/` for CI, with each test, its result and its skip reason.
- The seed of `bench/fuzz.lua` from the command line; seeds 1 to 50 go in the nightly tier.
- Write the CI matrix for TASK-42: release and dev build, `-j 1`, and `-j 4 --shuffle` (useful after the ticket that makes the waits into steps).

Read first: backlog/docs/designs/test-suite-review.md, sections 4 (T9), 7. backlog/docs/designs/testing-practices.md, sections 2.3 (L3), 3.2, 6 (BT9).

Overlaps: TASK-121 (shards), TASK-42 (CI), TASK-69 (done: paw keeps its own runner).

Size: S to M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An old binary with a new runtime fails at the start with a clear message
- [ ] #2 times.txt exists after a run
- [ ] #3 repeat 20 of a test that depends on order or time fails within the 20 runs (shown on one known flake)
- [ ] #4 --shuffle prints its seed, and the same seed gives the same order
- [ ] #5 The CI file lists each test with its result and its skip reason
- [ ] #6 The skills .claude/skills/lua-testing and .claude/skills/rust-testing name the new helpers and commands in the same commit.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Links (2026-11-22): the CI matrix with -j 4 --shuffle is useful after TASK-149. TASK-145 gives the quarantine list that repeat helps to empty.

Board review 2026-11-23: split into TASK-151.1 (one runner path, binary check, times) and TASK-151.2 (repeat, shuffle, CI file, fuzz seed, CI matrix). Set this ticket to Done when both are merged. Not on main: suite.sh has no repeat, shuffle or times.txt.

PO 2026-11-23: merged into TASK-145 (owner: fewer, larger tickets). Its criteria and text are in TASK-145.
<!-- SECTION:NOTES:END -->
