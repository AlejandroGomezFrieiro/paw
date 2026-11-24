---
id: TASK-337
title: Select split modes round-robin, keyswitch, cc and the select fade
status: To Do
assignee: []
created_date: '2026-11-23T23:40:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - agent:worker
milestone: m-18
dependencies:
  - TASK-280
priority: low
ordinal: 406000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From G2 (TASK-280). Only the index (manual) mode of the select split plays; a change of index uses the general 5 ms fade. Build the other modes and the select fade from the devices-graph design.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each mode picks its branch as designed (engine tests), and a change of branch fades with the select fade
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
