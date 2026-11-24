---
id: TASK-222.3
title: >-
  Export E3+E4a: the paw.export plan module and the :export command for sound
  (plan float, queue, progress, result, <Space>e keys)
status: Done
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T13:48:00Z'
labels: []
milestone: m-2
dependencies:
  - TASK-222.1
parent_task_id: TASK-222
priority: high
ordinal: 256000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: a Teal module that turns the grammar into a plan of files with names ({project} {track} {group} {region} {n} {date}). Size M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 paw.export.plan(words) turns the grammar of export.md section 2 into a list of renders: each with its file, tracks, time, tap and channels. Table tests cover an Ex range of tracks, an Ex range of time, in=loop, in=<region>, each=group|track|region|clip, two each= joined, a preset, and words after a preset that win
- [ ] #2 Test: the names use the fields {project} {track} {group} {tracks} {region} {n} {date}; with each= and no field paw adds the field; two files of one name get a number; a target with no folder goes into renders/
- [ ] #3 Test: a muted track is left out and named in the plan; a range of only muted tracks gives a clear message and no plan; a dynamics device on a group or on the master gives a note in the plan
- [ ] #4 paw.stems, paw.render_stems and paw.stems.plan are gone; their callers use paw.export; the module is Teal with no any; tools/tlcheck.sh passes
- [ ] #5 (TASK-222.4) Tests with real keys: :export writes renders/<project>.wav; :17,32export bridge.wav writes those bars; :t/Drums/export drums.wav writes the group alone through the master
- [ ] #6 (TASK-222.4) Test: an export of more than one file, or one that replaces a file outside renders/, shows the plan float first; y or Enter writes, n or Esc goes back; :export! skips the plan and replaces
- [ ] #7 (TASK-222.4) Test: the exports run in one queue; the status line shows the progress; Esc and :export.cancel cancel the whole queue; the result message names the files, length and peak; :messages keeps it; paw.export.last() gives the results
- [ ] #8 (TASK-222.4) The <Space>e keys of export.md 7.5 work in normal and visual mode; tests/leader_hints.lua lists the domain; keys.md and render.md say them; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented on branch worktree-agent-ae28da58cc292766b (commits 25e3a98a, 43da0248, e0de46cf, on main 2f970bba). New runtime/lua/paw/export.tl: plan of :export (presets mix/review/stems/tracks/regions, each=, tap=, channels=, in=, fields, names, renders/ default), plan float export.plan with left-out muted tracks and dynamics notes, one queue with status 'exporting i/n file pct · Esc cancels', Esc and :export.cancel, one message at the end, paw.export.last(). <Space>e keys (em es et er ee, visual too), <Space>tf/tF freeze keys; <Space>rR removed. paw.stems and paw.render_stems removed; :render stems, :render <Group>, stems=true and :stems go through paw.export. Docs: render.md :export section, keys.md, markers.md, freezing.md, about-teal.md. Tests: tests/export_sound.lua (+ golden stems_plan), updates in core, export, robust, tags, scope, guides_render, leader_hints. channels=auto in the stems/tracks presets needs TASK-222.2 kernel support. Not Done: waits for orchestrator build and full suite.

Landed on main in batch 17 (deb79a0f), with the merge fixes of 2026-11-23 (clock rounding, export leader domain, goldens, MCP render_stems).
<!-- SECTION:NOTES:END -->
