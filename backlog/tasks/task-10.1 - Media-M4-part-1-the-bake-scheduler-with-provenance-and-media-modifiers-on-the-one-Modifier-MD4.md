---
id: TASK-10.1
title: >-
  Media M4 part 1: the bake scheduler with provenance, and media modifiers on
  the one Modifier (MD4)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - media
  - bundle
milestone: m-5
dependencies:
  - TASK-75.1
  - TASK-294
references:
  - architecture/decisions/0025-render-with-provenance.md
  - architecture/decisions/0029-outside-programs-in-bake-jobs.md
  - architecture/decisions/0014-generic-modifier.md
parent_task_id: TASK-10
priority: medium
ordinal: 374000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle MD4 of backlog/docs/designs/architecture-plan.md V2.11 and V2.12 (phase 3). Child of TASK-10. The bake scheduler is an Upkeep of the agenda (EL2). A bake job runs a producer of tier bake and keeps its result with provenance (Recipe, SourceHash; ADR 0025). Opening a project never starts a bake; bakes start after the first edit or :bakes run. The media modifiers (TASK-10 M6, M7) use the Modifier of M1. Outside programs are not in this bundle (OP).

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
