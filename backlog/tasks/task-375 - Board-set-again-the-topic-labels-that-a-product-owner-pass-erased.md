---
id: TASK-375
title: 'Board: set again the topic labels that a product owner pass erased'
status: To Do
assignee: []
created_date: '2026-11-24T14:30:00Z'
labels:
  - board
  - agent:worker
dependencies: []
priority: low
ordinal: 444000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-11-24: a PO pass ran backlog task edit -l on 31 tickets and erased their topic labels (the board had no history then). Tickets: 298, 310, 311, 313-315, 317, 318, 320, 283-288, 308, 336, 338, 177, 297, 95, 95.3, 96, 97, 99, 307, 132, 206, 260, 289, 324, 332, 337, 339, 89, 94. Read each ticket and add topic labels from the labels in use on the board (backlog task list --plain, and the labels of related tickets), with --add-label only. Keep the agent: label.
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
