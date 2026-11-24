---
id: TASK-222.6
title: >-
  Export E6: :bounce with track and time ranges and tap=post (replaces
  :track.bounce)
status: To Do
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T08:19:00Z'
labels: []
milestone: m-2
dependencies:
  - TASK-222.1
  - TASK-223
parent_task_id: TASK-222
priority: medium
ordinal: 259000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: Builds on TASK-223's fix. Size S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: :bounce on a track writes a new audio track below it at tap=post, mutes the old track, is one undo step, and the message names the new track; through the master the song sounds the same (the tolerance of the freeze tests)
- [ ] #2 Test: :t2,t4bounce and :t'<,'>bounce bounce those tracks to one new track; :'<,'>bounce bounces only the time of the selection
- [ ] #3 Test: :bounce tap=pre gives the new track the fader, pan and sends of the old one
- [ ] #4 :track.bounce is gone; <Space>tb bounces; the docs that named :track.bounce say :bounce; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-223 (2026-11-23): the bounce fix leaves out the master only. A track inside a group still renders through the group, so the bounced track hears the group's devices and fader twice. tap=post (TASK-222.1) must render after the track's own fader and pan, without groups or master; :bounce uses it.

PO 2026-11-23: merged into TASK-222.2 (owner: fewer, larger tickets). Its criteria and text are in TASK-222.2.
<!-- SECTION:NOTES:END -->
