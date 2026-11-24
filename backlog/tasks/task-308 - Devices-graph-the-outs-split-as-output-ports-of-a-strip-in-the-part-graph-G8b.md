---
id: TASK-308
title: >-
  Devices graph: the outs split as output ports of a strip in the part graph
  (G8b)
status: To Do
assignee: []
created_date: '2026-11-23T16:01:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-16
dependencies: []
references:
  - architecture/decisions/0024-one-project-graph.md
  - architecture/decisions/0027-mix-as-graph-nodes.md
  - backlog/docs/designs/architecture-plan.md
priority: low
ordinal: 371000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle G8b of the architecture plan, version 2 (backlog/docs/designs/architecture-plan.md V2.13, V2.14). TASK-286 splits: the taps and :keys stay there (G8a). The outs split moves here.

After MX, the branches of an outs split (the further output pairs of a drum plugin) become output ports of the strip in the part graph, and wires go from each port to a node. Do not start before MX.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The outs split routes each output pair of a device to an output port of its strip; a wire from each port to a bus works (Rust test, null render)
- [ ] #2 The chain language and the devices view show the ports; docs are true; Vale reports 0 alerts
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
blocked-by-plan: starts after MX (architecture-plan.md V2.14).
<!-- SECTION:NOTES:END -->
