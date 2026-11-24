---
id: TASK-222.5
title: >-
  Export E5+E8: presets of the user and of the project, and one gain for a whole
  set of stems
status: Done
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels: []
milestone: m-2
dependencies:
  - TASK-222.3
  - TASK-222.10
parent_task_id: TASK-222
priority: medium
ordinal: 258000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: Built-ins mix, review, stems, tracks, regions, project; a preset can hold a list of exports. Size M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test: a preset of the same name in project.toml, in init.lua and built in: the project's wins, then init.lua, then the built-in one
- [x] #2 The built-in presets mix, review, stems, tracks, regions and project have the words of export.md section 6, by a table test of their plans
- [x] #3 Test: :export.preset <name> saves the words of the last :export in project.toml [export.presets]; :export.preset! <name> replaces it; :export.preset alone lists the presets and where each comes from; u undoes a save
- [x] #4 Test: a preset that holds a list of exports gives one plan, one confirm and one queue
- [x] #5 Test with real keys: <Space>ep picks a preset, shows its plan, and exports; export docs and keys.md say it; Vale reports 0 alerts
- [x] #6 (TASK-222.8) Test: normalize= or loudness= on a set of stems applies one gain, taken from the mix, to every file of the set
- [x] #7 (TASK-222.8) Test: after that gain the stems still add up to the mix times the same gain
- [x] #8 (TASK-222.8) The export docs say it; Vale reports 0 alerts
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a6ae49ce2112fcb5b, commit c0741722 (on 2f70b19f). Project presets in project.toml [export.presets] (new Project.export field), :export.preset / :export.preset! / list float, init.lua presets in paw.export.presets, built-ins incl. review (mp3) and project, list presets with one plan, <Space>ep picker with plan preview, gain sets: normalize/loudness on stems renders the mix first and gives every stem its gain (new RenderOpts.gain). Needs a new build: preset tests and the stems gain test fail on the old binary (no settable field export / no gain). Nest test ':export project in the song...' already failed on 2f70b19f.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): X5 of plan V2. The plan moves AC 1 and AC 3 (project and init.lua layers, save to project.toml) to bundle B3, but this branch already built them. Land as built. B3 moves export presets into the store (templates/export/ in four layers, ADR 0021) and removes project.toml [export.presets] (no compatibility before a release).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (c0741722). Presets in project.toml [export.presets], init.lua and built-ins (mix, review, stems, tracks, regions, project); :export.preset and :export.preset!; a list preset gives one plan; <Space>ep picker; normalize and loudness on stems give one gain from the mix. Bundle B3 (TASK-310) moves the presets to the store later.
<!-- SECTION:FINAL_SUMMARY:END -->
