---
id: TASK-289
title: >-
  Devices graph: docs final pass, guides for the three metal chains, tutor
  lesson and GIF (G13)
status: To Do
assignee: []
created_date: '2026-11-23T11:58:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:worker
milestone: m-16
dependencies:
  - TASK-283
  - TASK-284
  - TASK-287
  - TASK-318
documentation:
  - backlog/docs/designs/devices-graph.md
priority: medium
ordinal: 351000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each ticket of the milestone brings its docs; this ticket is the final pass. The device panel page becomes the devices view page, and the guides show real chains. Search README.md, docs/, the extension READMEs and .claude/skills for device panel, devices.json and Alt-j.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 docs/reference has the devices view page and the chain language page; device-panel.md is gone or redirects; key-rule.md, routing.md, devices.md and project-files.md are true
- [ ] #2 docs/explanation/about-device-graphs.md explains the tree, racks, templates and the chain language
- [ ] #3 How-to guides for parallel compression, a band split, racks and templates, and each of the three metal chains, each with a test in tests/guides_howto.lua
- [ ] #4 A tutor lesson and a GIF of the view (the paw-gifs skill)
- [ ] #5 Vale reports 0 alerts
<!-- AC:END -->

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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23 (plan V2 bundles): Bundle G13: also the graph view of GV (TASK-318).
<!-- SECTION:NOTES:END -->
