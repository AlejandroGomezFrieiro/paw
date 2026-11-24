---
id: TASK-222.8
title: 'Export E8: one gain for a whole set of stems with normalize= / loudness='
status: To Do
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T08:19:00Z'
labels: []
milestone: m-2
dependencies:
  - TASK-222.4
parent_task_id: TASK-222
priority: low
ordinal: 261000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: Size S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: normalize= or loudness= on a set of stems applies one gain, taken from the mix, to every file of the set
- [ ] #2 Test: after that gain the stems still add up to the mix times the same gain
- [ ] #3 The export docs say it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-222.5 (owner: fewer, larger tickets). Its criteria and text are in TASK-222.5.
<!-- SECTION:NOTES:END -->
