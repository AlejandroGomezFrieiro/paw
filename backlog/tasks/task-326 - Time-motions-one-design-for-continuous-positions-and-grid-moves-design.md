---
id: TASK-326
title: 'Time motions: one design for continuous positions and grid moves (design)'
status: Done
assignee: []
created_date: '2026-11-23T19:37:00Z'
updated_date: '2026-11-23T20:37:00Z'
labels:
  - design
  - ux
milestone: m-15
dependencies:
  - TASK-325
references:
  - architecture/decisions/0035-one-time-axis.md
priority: high
ordinal: 395000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-23, after recording: a take that ends off the grid puts the cursor off the grid after w/b, and grid moves then carry the offset; 'instead of improvising, make a consistent good design for how to mix continuous time and discrete time movements properly in our architecture to avoid strange UXs'. Design only, proposed ADR 0036. Uses the facts that TASK-325 reports.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A model of time positions: what is exact (ticks, samples, seconds, frames), what the grid is (adaptive to zoom or set, triplets, swing, meter and tempo changes, time folds), and how a position relates to it
- [ ] #2 One rule for each class of motion and edit (grid moves, edge and object moves, search and marks, counts, operators, selections, nudges, the mouse, recording, paste, split, stretch), the same in the arrange view, the piano roll and every lane kind
- [ ] #3 How the user sees and controls off-grid state (status, cursor, a snap key, options), checked against the key rule and Vim habits
- [ ] #4 Research of how other editors and DAWs do it (Vim, REAPER, Ableton, Bitwig, Logic or Cubase, a tracker), with what to copy and what not
- [ ] #5 Mock screens of the owner's case before and after, the tests by real keys, the plan (which bundle builds what), owner questions with recommendations
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
Design saved in backlog/docs/designs/time-motions.md; ADR 0036 proposed. Case 3 reproduced with the stepped engine (take end 5.312; w→5.312, l→6.312, l→7.312; take 2 recorded at 7.312–10.512; the cursor block straddles two ruler cells). Research: Vim, REAPER, Live, Bitwig, Logic, Cubase, Renoise. Build: TASK-327 (TM1), TASK-328 (TM2), TASK-329 (TM3). Waits for the owner's answers Q1-Q9.

Owner accepted ADR 0036 and Q1-Q9 as recommended (2026-11-23). Build: TASK-327 (TM1), TASK-328 (TM2), TASK-329 (TM3).
<!-- SECTION:NOTES:END -->
