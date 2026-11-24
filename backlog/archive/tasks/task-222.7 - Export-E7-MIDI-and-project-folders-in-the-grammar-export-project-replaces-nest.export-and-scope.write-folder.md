---
id: TASK-222.7
title: >-
  Export E7: MIDI and project folders in the grammar (:export project replaces
  :nest.export and :scope.write <folder>)
status: To Do
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T08:19:00Z'
labels: []
milestone: m-2
dependencies:
  - TASK-222.4
  - TASK-7.14
parent_task_id: TASK-222
priority: medium
ordinal: 260000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: Size M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: :export song.mid writes a type 1 Standard MIDI file with one track for each track of the range; :export clip riff.mid writes the clip at the cursor; each=track and each=clip write one file each
- [ ] #2 Test: :export clip riff.midi2 writes the clip as the project keeps it
- [ ] #3 Test: a word of sound on a MIDI target is refused by name (tap= is for sound; song.mid is MIDI)
- [ ] #4 Test: :export project <folder>/ writes the scope of the window (the song, a view, a subproject) as a project folder; :nest.export and :scope.write <folder> are gone, and :scope.write keeps only its meaning of saving a view as a subproject
- [ ] #5 subprojects.md, project-files.md and the export docs say it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-222.10 (owner: fewer, larger tickets). Its criteria and text are in TASK-222.10.
<!-- SECTION:NOTES:END -->
