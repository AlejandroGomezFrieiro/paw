---
id: TASK-41
title: 'Platforms 4: Android (and other interesting targets)'
status: To Do
assignee: []
created_date: '2026-11-21T19:33:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - platforms
  - android
milestone: m-1
dependencies: []
priority: low
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Explore Android: Oboe/AAudio audio, a touch-first frontend (the scene model allows a new frontend), files via SAF, no LuaJIT JIT on some devices (shares the portable-Lua work of Web 1, TASK-29). Also look at: ARM Linux boards (Raspberry Pi as a hardware groovebox), FreeBSD, and iOS feasibility. Output: a short feasibility note per target with a go/no-go.
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
