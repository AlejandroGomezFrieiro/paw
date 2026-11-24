---
id: TASK-188
title: >-
  Suite: a test fails when an event handler's error reaches the message line and
  the test did not expect it
status: Done
assignee: []
created_date: '2026-11-23T00:36:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels: []
milestone: m-12
dependencies: []
priority: medium
ordinal: 200000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-187 (2026-11-23): a render.before handler failed at every mix measurement and showed 'table index is nil' to the user, and the suite passed for months, because paw.try catches handler errors and no test looks at error messages. Make the runner record each error that paw.try (events.run, timers, keys) reports during a test, and fail the test unless it expected it (for example T.expect_error(pattern)). Measure first how many tests this fails today; fix them or list them with tickets, and the list only gets shorter.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A handler error during a test fails that test, by a test of the runner
- [ ] #2 Tests that expect an error say so
- [ ] #3 The list of tests that fail today is fixed or ticketed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a6c07026d44a92093, commit 4642aa17 (on top of merges of TASK-187 and TASK-180 branches). tests/suite.lua wraps paw.try and records each error (handlers, timers, jobs, keys); a test fails for an unexpected error or an expected error that does not come; T.expect_error(pattern); T.take_errors for the runner's own test (tests/runner_errors.lua). First count: 14 of 2146 tests. All fixed: ui.tl kept refused highlight groups (each termcolors change then failed in option.changed); record_mix fake render lacked seconds; shada typed :echo (no such command); 11 tests now declare their expected errors. No allow-list needed, no new tickets. Plugin tests (suite.sh plugins) not measured. Docs: docs/how-to/run-the-tests.md, lua-testing skill.
<!-- SECTION:NOTES:END -->
