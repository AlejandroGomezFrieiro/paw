---
id: TASK-316
title: >-
  Render with provenance: producers of tier kernel and bake, derived takes,
  freeze as a render with replace (RD)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:20:00Z'
labels:
  - agent:builder
  - architecture
  - render
  - bundle
milestone: m-17
dependencies:
  - TASK-312
  - TASK-75.3
  - TASK-214
  - TASK-303
references:
  - architecture/decisions/0025-render-with-provenance.md
  - architecture/decisions/0019-lanes-are-the-truth.md
  - architecture/decisions/0026-takes-and-comps-for-every-lane.md
priority: high
ordinal: 383000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle RD of backlog/docs/designs/architecture-plan.md V2.2, V2.7 step 7 and V2.12 (phase 5). paw.render(what, opts) turns a wire, a node output, a stack prefix or a derived take into a lane or a source take with provenance (ADR 0025). paw.producers.define(kind, spec) with tier, ports, span, run or job, and per-note controls. A derived lane is a lane that a Store wire feeds; its takes are Derived until the user renders one. Re-derive as a new take; :lane.detach cuts the link. Freeze becomes a render with replace (meta.frozen goes). The 50 ms limit is for all kernel jobs of one turn (V2.16 P4). A stub producer in the tests.

This ticket has a title and a description only. The product owner adds the acceptance criteria when its phase starts, from backlog/docs/designs/architecture-plan.md and the ADRs in the references. One Opus agent does the bundle.
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Lane heads: head on paw.producers.define; the pieces bake (states fresh/stale/progress/absent) and source; the head script (design: backlog/docs/designs/lane-heads.md)
<!-- SECTION:NOTES:END -->
