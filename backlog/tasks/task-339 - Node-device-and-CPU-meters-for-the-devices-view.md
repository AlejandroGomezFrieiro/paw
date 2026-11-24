---
id: TASK-339
title: Node, device and CPU meters for the devices view
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
ordinal: 408000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From G2 (TASK-280). G2 added Rust readers only (Shared::device_peak, device_time, Mapper::chain_peak). Give the devices view a Lua API for them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 paw.chain gives the peak of a node and branch and the CPU time of a device; the devices view shows them (golden screen)
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
G3 took the minimum: paw.chain.meters(owner) gives latency ms, peaks by id, device time ns. The rest stays here.
<!-- SECTION:NOTES:END -->
