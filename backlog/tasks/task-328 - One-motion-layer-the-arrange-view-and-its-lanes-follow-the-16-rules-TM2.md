---
id: TASK-328
title: 'One motion layer: the arrange view and its lanes follow the 16 rules (TM2)'
status: Done
assignee: []
created_date: '2026-11-23T19:52:00Z'
updated_date: '2026-11-24T14:34:00Z'
labels:
  - ux
  - bundle
milestone: m-15
dependencies:
  - TASK-327
references:
  - backlog/docs/designs/time-motions.md
  - architecture/decisions/0036-time-motions.md
priority: high
ordinal: 397000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/time-motions.md sections 3, 4, 6, 7, 8 (TM2). Rules 1-16, the pointer, the cursor drawn by its cell and CursorOff when off the grid, the status grid part with the offset, K, snap replaces note_snap. Docs: key-rule.md, keys.md, grammar.md, options.md, the arrange view reference, the tutor's lessons.
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
PO 2026-11-23: criteria come after the owner answers ADR 0036 (Q1 to Q9 change rules 1 to 16). Base them on the real-keys table of time-motions.md section 7.

ADR 0036 accepted 2026-11-23 with Q1-Q9 as recommended; take the criteria from backlog/docs/designs/time-motions.md section 8.

From TM1: h and l go to lines (today cursor.step keeps the offset); use want in row motions; shrink tools/gridlint-allowed.txt (18 files).

Wave 23 (2026-11-24), base 9cecbfdc (batches 20-22 + W1).

Merged in the merge tree (e82d0d69, 2026-11-24). The arrange view and its lanes follow the rules; TM3 owes the piano roll (cursor.step, axis:step_at). Option note_snap became snap. Order issue seen under filter 'move': 'recent: the newest project is first' sees folder1-unused from an earlier test (not from this change).

Orchestrator 2026-11-24: on main since e82d0d69 (Merge TM2). TM3 owes the piano roll. Status was left In Progress by mistake; the roadmap was right.
<!-- SECTION:NOTES:END -->
