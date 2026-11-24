---
id: TASK-387
title: 'Lua devices: count the events that Missed::keep drops when its buffer is full'
status: To Do
assignee: []
created_date: '2026-11-24T17:58:00Z'
labels:
  - agent:worker
dependencies: []
priority: low
ordinal: 456000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-356 review (2026-11-24): crates/paw-luadev/src/missed.rs:53, Missed::keep drops an event that the script should get when its buffer is full, and nothing counts it. The device still passes the event on, so this is a loss for the script, not for the output. Count it (an atomic in the device, as lua.drops, or in lua.misses) and say in docs/reference/lua-devices.md which count covers it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A full Missed buffer counts each event it does not keep; a test fills it and reads the count
- [ ] #2 docs/reference/lua-devices.md says which count covers it, and the lua.drops line also names the spill buffer
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
