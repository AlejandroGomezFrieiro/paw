---
id: TASK-75.4
title: >-
  Modifier stacks 4: the stack panel, :clip.recipe as chain text, lane stacks
  (M4)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-23T17:01:00Z'
labels:
  - nondestructive
  - midi
  - bundle
milestone: m-5
dependencies:
  - TASK-75.2
  - TASK-75.3
  - TASK-283
  - TASK-309
references:
  - architecture/decisions/0022-modifier-stack-ux.md
  - architecture/decisions/0012-generic-chain-language.md
parent_task_id: TASK-75
priority: medium
ordinal: 376000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle M4 of backlog/docs/designs/architecture-plan.md V2.11 (phase 4). The stack panel (<Space>cs, the inspector rows of the devices view), <Space>ca and <Space>cA, \a and \t (ADR 0022). :clip.recipe is chain-language text, off disables an entry, :w is one undo step. The lane stack runs after the stack of each clip (ADR 0026, LA gives the field).

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
Lane heads: the piece stack (design: backlog/docs/designs/lane-heads.md)
<!-- SECTION:NOTES:END -->
