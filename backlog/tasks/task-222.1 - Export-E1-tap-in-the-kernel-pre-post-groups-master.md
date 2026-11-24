---
id: TASK-222.1
title: 'Export E1: tap= in the kernel (pre, post, groups, master)'
status: Done
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels: []
milestone: m-2
dependencies: []
parent_task_id: TASK-222
priority: high
ordinal: 254000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: paw.render and session/render.rs take tap=; tests that each tap renders what it names and that groups and master add up to the mix. Size M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 paw.render and the kernel render (session/render.rs) take tap=pre|post|groups|master, with master as the default; master=false is gone and its callers use tap=groups
- [x] #2 Rust test: a track with a device, a fader and pan change, in a group with a device, under a master with a device: each tap renders what section 3 of export.md names
- [x] #3 Test: the files of the top-level groups (and the tracks outside a group) add up to the mix at tap=master, and to the mix without the master's devices and fader at tap=groups (the tolerance of the freeze tests, no dynamics device)
- [x] #4 The no_alloc tests pass; render.md names tap=; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
tap=pre|post|groups|master in paw.render and session/render.rs (Tap enum; freeze::tracks_alone with Fader::Out/In generalizes freeze::alone). pre/post need tracks; groups = old master=false (kept until E4); tap=master with master=false errors; freeze/block always without master and refuse tap=. post is after the track's own fader and pan only, no groups/sends/master (the bounce case of TASK-223). Glue uses tap=groups. Tests: tests/core.lua 'a render listens at the point of the signal that tap names'; freeze.rs unit test for a member listed with its group. Docs: render.md Lua section, api.md regenerated. Branch worktree-agent-aa0ecb841e96d0e70, commit eaaeeed6.

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
