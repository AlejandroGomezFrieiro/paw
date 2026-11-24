---
id: TASK-96.5
title: >-
  Typed API 5: the frontend state as typed structs in paw-proto (waits for the
  window)
status: To Do
assignee: []
created_date: '2026-11-23T06:14:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - architecture
  - api
  - gui
milestone: m-13
dependencies: []
parent_task_id: TASK-96
priority: low
ordinal: 236000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-96. Read its description first. The frontend state becomes typed structs in paw-proto with generated Teal records, and paw-gui reads fields in place of its 192 string keys. paw-gui is paused (owner, 2026-11-22), so this part waits in m-13 until the owner starts the window again.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The frontend state is typed structs in paw-proto with generated Teal records
- [ ] #2 paw-gui reads fields, not string keys; its tests pass
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
