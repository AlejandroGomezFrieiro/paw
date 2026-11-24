---
id: TASK-315
title: >-
  Curve lanes: automation is a lane of kind curve that feeds a node parameter
  (CV)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-17
dependencies:
  - TASK-312
references:
  - architecture/decisions/0027-mix-as-graph-nodes.md
  - architecture/decisions/0018-parts-and-typed-lanes.md
priority: medium
ordinal: 382000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle CV of backlog/docs/designs/architecture-plan.md V2.5 and V2.7 step 5 (phase 5). Track.lanes of automation become lanes of base curve with a Live wire to Param(strip, key); Target::State becomes a lane of base state; the automation mode is a field of the strip (ADR 0027). The word lane stays true for the user (V2.16 P12). The null test of renders again. TASK-238 (send automation) and the automation part of TASK-235 build on it.

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
