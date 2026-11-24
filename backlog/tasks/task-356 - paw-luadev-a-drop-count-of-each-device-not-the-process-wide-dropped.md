---
id: TASK-356
title: 'paw-luadev: a drop count of each device, not the process-wide dropped()'
status: In Progress
assignee: []
created_date: '2026-11-24T11:30:00Z'
updated_date: '2026-11-24T17:53:00Z'
labels:
  - agent:worker
  - rust
  - tests
milestone: m-12
dependencies: []
priority: low
ordinal: 425000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-354 review (2026-11-24): crates/paw-luadev/src/device.rs tests assert the process-wide dropped() as a before/after difference. Not flaky today (nextest runs a process per test, and no other luadev test drops), but a new test that drops an event would make it fail under cargo test. Give each device its own drop count (an atomic in the device, read by the health line) and assert on that. Also device.rs:514: a push into spilled past MAX_EVENTS is lost and not counted; count it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each Lua device has its own drop count (an atomic in the device); the health line and the tests read it, not the process-wide dropped()
- [ ] #2 A push into spilled past MAX_EVENTS (device.rs) is counted as a drop; a test overflows it and sees the count
- [ ] #3 The tests pass under cargo test in one process as well as under nextest (no test depends on another's drops)
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
Started 2026-11-24: branch luadev-drops, base 6b819e3e.
<!-- SECTION:NOTES:END -->
