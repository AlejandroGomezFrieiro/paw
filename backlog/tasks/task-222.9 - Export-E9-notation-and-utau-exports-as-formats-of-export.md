---
id: TASK-222.9
title: 'Export E9: notation and utau exports as formats of :export'
status: To Do
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels: []
milestone: m-11
dependencies:
  - TASK-222.3
parent_task_id: TASK-222
priority: low
ordinal: 262000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/export.md (TASK-222), approved by the owner 2026-11-23 with all its recommendations: one command :export; stems = groups, tracks = one file per track; :export tracks taps post; mono (L+R)/2; channels stereo by default, auto in the stems and tracks presets; replace files freely in renders/, elsewhere after the plan or with !; tail 2 s; presets project > init.lua > built-in; :export project inside a subproject's scope replaces :nest.export; :utau.freeze moves onto :freeze later. No compatibility before a release: remove what overlaps. Read the design section of this part before you start.

This part: After notation and utau move to Rust. Size M.
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Each acceptance criterion is met, and the notes give its evidence
- [ ] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [ ] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [ ] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [ ] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [ ] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [ ] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [ ] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->
