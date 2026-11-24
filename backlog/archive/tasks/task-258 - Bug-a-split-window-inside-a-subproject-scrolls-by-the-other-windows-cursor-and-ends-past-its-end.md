---
id: TASK-258
title: >-
  Bug: a split window inside a subproject scrolls by the other window's cursor
  and ends past its end
status: To Do
assignee: []
created_date: '2026-11-23T07:30:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - bug
  - nest
  - ux
milestone: m-2
dependencies: []
priority: medium
ordinal: 322000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-226. With two windows, one in the song and one inside a subproject, the window that is not current scrolls by the one shared cursor, which is in the other window's time; it shows bar 25 of an 8-bar subproject. Each window must keep a place in its own time. Screens: scratchpad/ux/v1.txt (split).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A golden screen test with real keys: a split, one window in a subproject, moving in the other window leaves the subproject window inside its bars
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-257 (owner: fewer, larger tickets). Its criteria and text are in TASK-257.
<!-- SECTION:NOTES:END -->
