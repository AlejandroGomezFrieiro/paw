---
id: TASK-151.2
title: >-
  Lua runner 2: repeat, shuffle with a seed, a TAP or JUnit file for CI, the
  fuzz seed
status: To Do
assignee: []
created_date: '2026-11-23T06:13:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-151.1
parent_task_id: TASK-151
priority: medium
ordinal: 228000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-151. Read its description first.

- suite.sh repeat N only "<words>": stop at the first failure and print the run number.
- suite.sh --shuffle <seed>: print the seed; the same seed gives the same order.
- A TAP or JUnit file in target/test-scratch/ for CI, with each test, its result and its skip reason.
- The seed of bench/fuzz.lua from the command line; seeds 1 to 50 go in the nightly tier (TASK-145).
- Write the CI matrix for TASK-42: release and dev build, -j 1, and -j 4 --shuffle.
- Change the skills lua-testing and rust-testing, and the how-to page on the tests, in the same commit.

Size: S to M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 repeat 20 of a test that depends on order fails within the 20 runs (shown on a fixture test that fails on its second run)
- [ ] #2 --shuffle prints its seed, and the same seed gives the same order
- [ ] #3 The CI file lists each test with its result and its skip reason
- [ ] #4 bench/fuzz.lua takes its seed from the command line
- [ ] #5 The skills and the how-to page name the new commands; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-145 (owner: fewer, larger tickets). Its criteria and text are in TASK-145.
<!-- SECTION:NOTES:END -->
