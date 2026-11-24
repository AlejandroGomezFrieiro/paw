---
id: TASK-222.4
title: >-
  Export E4a: the :export command for sound: plan float, queue, progress,
  result, <Space>e keys
status: To Do
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T08:19:00Z'
labels: []
milestone: m-2
dependencies:
  - TASK-222.3
parent_task_id: TASK-222
priority: high
ordinal: 257000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: Removes :render, :render stems, :stems, :render.regions; :render.cancel/.tags become :export.*. Docs and guides change in the same commit. Size L.
This part (E4a, split by the PO on 2026-11-23 from an L ticket): the :export command for sound over paw.export (E3): the plan float (export.md 7.1), the queue and progress on the status line (7.2), the result message and paw.export.last() (7.3), the names and folders (7.4), completion of the words, and the keys of 7.5 (<Space>ee, em, es, et, er; <Space>tf and <Space>tF; the visual forms). <Space>ep comes with E5 and <Space>tb with E6. The old commands stay until E4b (TASK-222.10) removes them, so this branch stays small. Size M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tests with real keys: :export writes renders/<project>.wav; :17,32export bridge.wav writes those bars; :t/Drums/export drums.wav writes the group alone through the master
- [ ] #2 Test: an export of more than one file, or one that replaces a file outside renders/, shows the plan float first; y or Enter writes, n or Esc goes back; :export! skips the plan and replaces
- [ ] #3 Test: the exports run in one queue; the status line shows the progress; Esc and :export.cancel cancel the whole queue; the result message names the files, length and peak; :messages keeps it; paw.export.last() gives the results
- [ ] #4 The <Space>e keys of export.md 7.5 work in normal and visual mode; tests/leader_hints.lua lists the domain; keys.md and render.md say them; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-222.3 (owner: fewer, larger tickets). Its criteria and text are in TASK-222.3.
<!-- SECTION:NOTES:END -->
