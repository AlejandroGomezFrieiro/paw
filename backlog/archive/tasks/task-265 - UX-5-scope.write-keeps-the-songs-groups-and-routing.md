---
id: TASK-265
title: 'UX-5: :scope.write! keeps the song''s groups and routing'
status: To Do
assignee: []
created_date: '2026-11-23T07:52:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - ux
  - nest
milestone: m-15
dependencies:
  - TASK-257
priority: high
ordinal: 329000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/scopes-ux.md (approved by the owner 2026-11-23, all recommendations). Each change gets T.expect_screen golden tests at 100x30 with the real keys; put a before/after screen in the report.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 :scope.write! of a group view keeps the group and puts the return row in it, so no route changes; when a route must change the message names it; a view over several buses gives one row to the master and names the buses, and a 'stems' word keeps them; subprojects.md says so
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-257 (owner: fewer, larger tickets). Its criteria and text are in TASK-257.
<!-- SECTION:NOTES:END -->
