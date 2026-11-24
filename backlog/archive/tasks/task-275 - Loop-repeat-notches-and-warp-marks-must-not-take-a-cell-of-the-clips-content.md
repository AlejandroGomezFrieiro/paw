---
id: TASK-275
title: Loop repeat notches and warp marks must not take a cell of the clip's content
status: To Do
assignee: []
created_date: '2026-11-23T08:12:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - ux
milestone: m-15
dependencies: []
priority: medium
ordinal: 339000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-270 (clips 1 to 1). The notch where each repeat of a looped clip begins, and the warp marks of an audio clip, still draw over a cell of the clip's body, so that cell hides its notes or sound. Draw them on the name row or as a style, as TASK-270 did for the clip edge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A golden screen: a looped clip with a note on each repeat's first beat shows that note in the repeat's first cell; the same for a warp mark over sound
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-273 (owner: fewer, larger tickets). Its criteria and text are in TASK-273.
<!-- SECTION:NOTES:END -->
