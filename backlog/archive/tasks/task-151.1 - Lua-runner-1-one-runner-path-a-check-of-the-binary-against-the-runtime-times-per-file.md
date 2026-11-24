---
id: TASK-151.1
title: >-
  Lua runner 1: one runner path, a check of the binary against the runtime,
  times per file
status: To Do
assignee: []
created_date: '2026-11-23T06:13:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-146
parent_task_id: TASK-151
priority: medium
ordinal: 227000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-151. Read its description first.

- crates/paw-tui/tests/suite.rs runs tests/tools/suite.sh, so there is one runner path with one set of folders.
- The runner compares a version stamp of the kernel API with the runtime, and fails at the start when they differ. Today an old binary (PAW_TEST_BIN) with a new runtime prints Lua errors and the suite still says all passed.
- The runner writes the wall time of each file to target/test-scratch/times.txt. This is information only, never a failure.
- Change the skills lua-testing and rust-testing in the same commit.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An old binary with a new runtime fails at the start with a clear message (a test of the runner with a wrong stamp)
- [ ] #2 cargo test -p paw-tui --test suite and tests/tools/suite.sh run the same runner
- [ ] #3 times.txt exists after a run, one line for each file
- [ ] #4 The skills lua-testing and rust-testing name the change
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: start it after part 2 of TASK-146 merges. Both change the runner (tests/tools/suite.sh, tests/suite.lua); in parallel they conflict.

PO 2026-11-23: merged into TASK-145 (owner: fewer, larger tickets). Its criteria and text are in TASK-145.
<!-- SECTION:NOTES:END -->
