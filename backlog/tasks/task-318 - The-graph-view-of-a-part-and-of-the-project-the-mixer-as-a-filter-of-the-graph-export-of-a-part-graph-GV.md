---
id: TASK-318
title: >-
  The graph view of a part and of the project; the mixer as a filter of the
  graph; export of a part graph (GV)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-16
dependencies:
  - TASK-312
  - TASK-283
references:
  - architecture/decisions/0024-one-project-graph.md
  - architecture/decisions/0027-mix-as-graph-nodes.md
  - architecture/decisions/0003-one-view-two-frontends.md
priority: medium
ordinal: 385000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle GV of backlog/docs/designs/architecture-plan.md V2.7 step 10 (phase 5). A view of the part graph and of the project graph, in one Lua view for both frontends (ADR 0003). The mixer view becomes the graph filtered to strips, buses, sends and master, drawn as columns (ADR 0027). paw.graph.of(owner) and paw.graph.project(): connect, disconnect, export, import. Design with golden screens first (owner: UX first).

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
