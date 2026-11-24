---
id: TASK-212
title: 'projdiff: Enter on a change inside a subproject goes into that subproject'
status: To Do
assignee: []
created_date: '2026-11-23T06:35:00Z'
updated_date: '2026-11-23T08:19:00Z'
labels:
  - projdiff
  - extensions
  - nest
  - keys
milestone: m-2
dependencies:
  - TASK-7.15
  - TASK-210
priority: medium
ordinal: 240000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-7.15 (its agent named it). The window of :Pdiff and its quickfix list now show a change inside a subproject under the subproject's name. Enter on such a change was not checked: it must go inside that subproject (as a choice of :nest.list does) and put the cursor on the changed track or clip. For a subproject inside a subproject, Enter goes into the inner one.

Read first: extensions/projdiff/lua/projdiff/view.lua and diff.lua; runtime/lua/paw/nest.tl (go inside a subproject); docs/reference/subprojects.md; tests/scope.lua; extensions/projdiff/tests.lua (the TASK-7.15 tests).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: <Space>gd, then Enter on a change inside a subproject, puts the window in the subproject's scope with the cursor on the changed track
- [ ] #2 Test: Enter on a change two levels deep goes into the inner subproject
- [ ] #3 Test: Enter on a change of the song does what it did before
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: TASK-210 also changes projdiff. Start this one after TASK-210, or keep the change to view.lua and diff.lua.

PO 2026-11-23: dependency on TASK-210 added (both change projdiff; start after it merges).

PO 2026-11-23: merged into TASK-211 (owner: fewer, larger tickets). Its criteria and text are in TASK-211.
<!-- SECTION:NOTES:END -->
