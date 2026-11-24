---
id: TASK-355
title: 'Key layer: each action declares how it joins dot repeat and undo'
status: To Do
assignee: []
created_date: '2026-11-24T11:10:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - agent:builder
  - ux
  - keys
milestone: m-10
dependencies: []
priority: medium
ordinal: 424000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Idea from modalkit (2026-11-24): its ApplicationAction gives each action a SequenceStatus (Atom, Break, Ignore) for dot repeat, undo grouping and selection memory. In paw, 'one user action is one undo step' and what '.' repeats are conventions in keymap.tl and commands.tl. Make them a declared property of each command and key action (for example repeat = 'atom'|'break'|'ignore', undo = 'own'|'join'|'none'), checked when a command registers, so a test or an agent can list the commands whose undo or repeat is undeclared. Design first (contract change: architecture skill, a proposed ADR), then build. Not a core-model change; it can wait for the foundation tickets.
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
