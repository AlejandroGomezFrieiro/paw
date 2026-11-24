---
id: TASK-388
title: >-
  Terminal: cells that are wide, combining, emoji or control characters keep the
  frame in its columns
status: To Do
assignee: []
created_date: '2026-11-24T18:01:00Z'
labels:
  - agent:worker
dependencies: []
priority: medium
ordinal: 457000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-384 audit (2026-11-24). (1) Rename a part to a name with an emoji, a variation selector or a combining mark: its row shifts, because write_cells advances the cursor by paw's width and the terminal uses its own. (2) A name with control characters (a tab, ESC [2J) is written raw to the terminal. Fix: grapheme cells with unicode-width, a cursor move after each cell that is not ASCII; grid.text shows C0, C1 and DEL as visible marks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A part named with an emoji, a variation selector and a combining mark keeps every column of its row and the rows below in place; a test in a pseudo-terminal
- [ ] #2 A name with C0, C1 or DEL characters shows visible marks and sends no control sequence to the terminal; a test
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
