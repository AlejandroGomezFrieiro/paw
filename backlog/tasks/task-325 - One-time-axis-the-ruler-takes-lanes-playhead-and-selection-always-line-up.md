---
id: TASK-325
title: 'One time axis: the ruler, takes, lanes, playhead and selection always line up'
status: Done
assignee: []
created_date: '2026-11-23T19:10:00Z'
updated_date: '2026-11-23T23:03:00Z'
labels:
  - ux
  - bundle
milestone: m-15
dependencies: []
references:
  - architecture/decisions/0035-one-time-axis.md
priority: high
ordinal: 394000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-23, after recording: 'there are still problems with alignment between takes, the timeline ruler etc. … these imprecisions make stuff hard to manage, so let's make sure all the lines are always well aligned in the new design'. TASK-271 fixed only the start column. arrange.tl maps time to columns in several ways (m.view/m.beat through folds, scroll + x / zoom, half cells for waveforms). Build one axis (ADR 0035) and move every row, the ruler, the playhead, the selection and the mouse onto it, on today's code (the owner records with it now); the new lanes, takes and heads then build on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An audit lists each place that maps time to columns or columns to time (arrange*, tempolane, curve, pianoroll, extensions), with the misalignments found, each shown in a before screen of a recording scenario (takes, comp, loop, punch, count-in)
- [x] #2 One axis module gives x_of, beat_of and the cell span; every row, the ruler, the playhead, the selection, loop and punch ranges, grid lines and the mouse use it
- [x] #3 A test draws one project with each kind of row at several zooms, scrolls and folds and checks a beat is at the same column on each row (real keys to zoom and scroll)
- [x] #4 A lint refuses / zoom or * zoom outside the axis module
- [x] #5 Golden screens before and after; each change of a cell is explained
- [x] #6 The cursor is kept only as an exact beat or tick, never as a column; its column comes from the axis on each draw; a real-keys test of a long sequence of moves, zooms, scrolls, a take and a tempo change checks after each step that the cursor's column is the ruler's column of its beat and the beat has no drift
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-23: 'the cursor can get out of sync with the ruler; if I move it back to 1.1.1 and then move it it recovers its alignment. Let's make sure the cursor state vs the timeline is always correct when we rebuild it.' Sent to the agent.

Owner 2026-11-23: 'if a clip stops recording off-the-grid and I do w and b to move, then the cursor becomes offset since the clip might finish off-the-grid, which then can build up. The UX is pretty bad due to this, it needs to improve.' Decision: h/l go to grid lines, not +/- a step; w/b/e keep exact edges; off-grid shown; snap key. Sent to the agent.

Owner 2026-11-23: 'instead of improvising, make a consistent good design for how to mix continuous time and discrete time movements properly in our architecture to avoid strange UXs'. The move rules (AC 7-8) are removed here and go to the time-motion design ticket; this ticket keeps the axis, the exact cursor and alignment, and reports the facts for the design.

From TASK-326: the design assumes (a) the axis puts a beat in the cell that contains it, (b) the cursor is kept as an exact beat; TM1 (TASK-327) makes it an integer tick (TPQ 61440). Do not change h/l semantics here.

Branch worktree-agent-ad3883f4e3e9cb64b, commit 04eabc6b (base 7e5a2603). paw.axis (axis.tl) for every row, ruler, playhead, cursor, selection, loop/punch, grid, folds, mouse, roll, curve editor, plot, harmony, utau, mixdiag. Found: boxes rounded to nearest while content used floor (content a cell off), waveforms spread over the rounded width, take rows ignored folds, punch/recording in song time not window time, cursor width floor(grid*zoom), each editor its own rounding; cursor drift from nearest-cell display and float sums of l/h. Tests tests/time_axis.lua (6), tests/zoomlint.lua (2); lint tools/zoomlint.lua. Move semantics unchanged. Joins batch 20. Architecture edits staged in scratchpad/pending-arch/T325-axis.md.

On main in batch 20 (5041115e, pushed 2026-11-24 with the tag pre-parts). Full suite passed after one test fix (5041115e: three tests and the time-axis test expected the null backend); nix flake check passed.

PO 2026-11-24: ACs checked against main: runtime/lua/paw/axis.tl, tests/time_axis.lua, tools/zoomlint.lua with the flake check zoomlint, golden screens of takes against the ruler in commit 04eabc6b.
<!-- SECTION:NOTES:END -->
