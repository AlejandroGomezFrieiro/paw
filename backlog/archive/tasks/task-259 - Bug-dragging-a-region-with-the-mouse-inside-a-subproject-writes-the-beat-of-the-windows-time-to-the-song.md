---
id: TASK-259
title: >-
  Bug: dragging a region with the mouse inside a subproject writes the beat of
  the window's time to the song
status: To Do
assignee: []
created_date: '2026-11-23T07:30:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - bug
  - nest
milestone: m-2
dependencies: []
priority: low
ordinal: 323000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-226. Regions now draw in the window's time (paw.markers.placed), but a mouse drag of a region still writes that beat to the song's marker; it must write the song beat. Also note: offsets through nested subprojects are approximate when an outer subproject has its own tempo.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A drag of a region inside a subproject moves it to the song beat under the mouse (test with mouse events)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-257 (owner: fewer, larger tickets). Its criteria and text are in TASK-257.
<!-- SECTION:NOTES:END -->
