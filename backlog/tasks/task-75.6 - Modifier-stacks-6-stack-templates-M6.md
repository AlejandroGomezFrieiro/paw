---
id: TASK-75.6
title: 'Modifier stacks 6: stack templates (M6)'
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-23T16:19:00Z'
labels:
  - nondestructive
  - templates
  - bundle
milestone: m-5
dependencies:
  - TASK-75.4
  - TASK-298
references:
  - architecture/decisions/0031-templates-shape-content-linked.md
  - architecture/decisions/0022-modifier-stack-ux.md
parent_task_id: TASK-75
priority: low
ordinal: 389000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle M6 of backlog/docs/designs/architecture-plan.md V2.11 (phase 5). A stack is a template of kind stack in the store (\t saves one; ADR 0031). Size S.

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
