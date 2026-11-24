---
id: TASK-149.6
title: 'Tests to steps 6: the live tier, -j 4 by default, and the docs'
status: To Do
assignee: []
created_date: '2026-11-23T06:13:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-149.1
  - TASK-149.2
  - TASK-149.3
  - TASK-149.4
  - TASK-149.5
  - TASK-151
parent_task_id: TASK-149
priority: medium
ordinal: 226000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Last part of TASK-149. Read the description of TASK-149 first.

When parts 1 to 5 are merged: count the live tests (T.live or tests/live_<area>.lua; owner, 2026-11-22: about 3 % of the suite, fewer than 60). Each live test checks outcomes only. Make -j 4 the default of tests/tools/suite.sh (owner: shards only after the waits are steps). Change the how-to page on the tests and the skill lua-testing. Run the full suite in a dev build and in a release build, and three times with -j 4 --shuffle and three seeds.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fewer than 60 tests are live, and each checks outcomes only
- [ ] #2 suite.sh -j 4 --shuffle <seed> passes three times with three seeds
- [ ] #3 The full suite passes in a dev build and in a release build
- [ ] #4 -j 4 is the default of suite.sh; the how-to page and the skill lua-testing say so; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-149 (owner: fewer, larger tickets). Its criteria and text are in TASK-149.
<!-- SECTION:NOTES:END -->
