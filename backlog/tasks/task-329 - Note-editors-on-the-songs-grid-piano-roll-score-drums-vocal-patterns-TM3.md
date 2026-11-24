---
id: TASK-329
title: >-
  Note editors on the song's grid: piano roll, score, drums, vocal, patterns
  (TM3)
status: To Do
assignee: []
created_date: '2026-11-23T19:52:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - agent:builder
  - ux
  - bundle
milestone: m-15
dependencies:
  - TASK-327
references:
  - backlog/docs/designs/time-motions.md
  - architecture/decisions/0036-time-motions.md
priority: high
ordinal: 398000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/time-motions.md sections 3.1, 8 (TM3). The roll's grid and cursor in song ticks (today its grid starts at the active clip); the score, drum grid, vocal editor and pattern view on paw.timegrid; cell views mark an off-grid thing in its cell. Fold into PR1 as criteria if PR1 has not started.
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
PO 2026-11-23: TASK-307 (PR) is design only and has not started. Its build bundle is TASK-75.5 (M5). Keep TM3 as its own bundle after TM1; it gives criteria to PR's design. Add criteria after the owner answers ADR 0036.

ADR 0036 accepted 2026-11-23 with Q1-Q9 as recommended; take the criteria from backlog/docs/designs/time-motions.md section 8.

From TM1: the roll and the vocal editor cursors keep a tick and want (they still keep float beats).
<!-- SECTION:NOTES:END -->
