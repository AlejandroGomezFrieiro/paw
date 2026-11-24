---
id: TASK-322
title: 'Lane heads: design study (a kind gives its head; the default head from pieces)'
status: Done
assignee: []
created_date: '2026-11-23T16:48:00Z'
updated_date: '2026-11-23T17:19:00Z'
labels:
  - design
milestone: m-10
dependencies: []
references:
  - architecture/decisions/0034-lane-heads-by-kind.md
priority: medium
ordinal: 391000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-23: a script or transformation lane does not need the head of an audio or video lane; a diffsinger lane may show the singer's picture; paw needs a default head. Design only: the head contract (render, rows, local keys) in the editor subject of the kind (TASK-177), the default head as pieces, what the core keeps (track column, marks, keys), pictures in the terminal, lane height, redraw, and before/after screens. Proposed ADR 0034.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A design with the contract as a Teal record, the pieces of the default head, and how today's header code maps onto them
- [ ] #2 Mock screens at 3 widths: the default head, a diffsinger head with a picture (half-block fallback too), a script lane, a video lane, a part head
- [ ] #3 The keys: what the core keeps, what a head adds, and the key rule checked
- [ ] #4 The plan: which bundle builds what (TASK-177 B7, TASK-306 B6, piano roll PR2), with the tests and golden screens
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
Design delivered by agent a240d464 (no commits; base deb79a0f): contract in section 4, pieces and default heads in 6, mapping of today's code in 7, mock screens at 60/100/140 in 8 (today's screens in 2, from the shared binary), keys and the key rule in 9, height 10, redraw 11, mouse 12, plan and tests 13, ADR edits 14, owner questions Q1-Q9 in 15. Follow-ups: TASK-323 (HD), TASK-324 (utau vocal head) (design: backlog/docs/designs/lane-heads.md)

Owner accepted the design and Q1-Q9 as recommended (2026-11-23); ADR 0034 accepted. Build: TASK-323 (HD), TASK-324 (utau vocal head).
<!-- SECTION:NOTES:END -->
