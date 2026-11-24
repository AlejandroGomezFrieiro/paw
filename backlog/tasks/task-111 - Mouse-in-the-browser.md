---
id: TASK-111
title: Mouse in the browser
status: To Do
assignee: []
created_date: '2026-11-22T11:00:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - web
  - ux
  - mouse
milestone: m-0
dependencies: []
priority: medium
ordinal: 114000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-22: people who want a mouse must be able to use paw in the browser. Terminal in the page: xterm.js mouse reporting (SGR 1006) into paw-tui's mouse support (clicks, drags, wheel on clips, ruler, track headers, mixer), with the split-ESC fix (TASK-106); test both the BrowserPod demo and the emscripten app; later the window frontend on WebGPU (TASK-34). Measure and fix any gesture that the terminal path lacks.
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
