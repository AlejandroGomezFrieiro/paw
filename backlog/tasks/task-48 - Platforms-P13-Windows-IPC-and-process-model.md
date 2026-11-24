---
id: TASK-48
title: 'Platforms P13: native Windows IPC and processes (deferred)'
status: To Do
assignee: []
created_date: '2026-11-21T19:52:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - platforms
  - windows
milestone: m-1
dependencies: []
priority: low
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deferred: Windows goes through WSL (TASK-40). Kept as the record of what a native port needs: Unix sockets to named pipes (interprocess), pre_exec/PDEATHSIG/process groups to handle inheritance + Job objects, shm + wake-up via file mapping + Event objects. The platform layer (TASK-51) must keep this possible.
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
