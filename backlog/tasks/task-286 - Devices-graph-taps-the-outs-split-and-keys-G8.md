---
id: TASK-286
title: 'Devices graph: taps and :keys (G8a)'
status: To Do
assignee: []
created_date: '2026-11-23T11:58:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-16
dependencies:
  - TASK-280
documentation:
  - backlog/docs/designs/devices-graph.md
priority: medium
ordinal: 348000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A side-chain key can come from another track (as today) or from a node of the same graph (a tap, key=@in or key=@<id>). The outs split gives the further output pairs of a drum plugin their own branches. The metal chains use six keys on one bus, so :keys lists them. Design section 4.5 and 9.7.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 key=@in and key=@<id> work; a tap to a later node is refused
- [ ] #2 :keys lists each key of the chain and where it comes from
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
PO 2026-11-23 (plan V2 bundles): Split (architecture-plan.md V2.13): this ticket is G8a (taps and :keys). The outs split (old AC 2) moved to G8b, TASK-308, after MX. Taps use NodeId; refuse a tap to a later node with ChainError.
<!-- SECTION:NOTES:END -->
