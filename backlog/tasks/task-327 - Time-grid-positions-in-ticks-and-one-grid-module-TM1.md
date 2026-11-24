---
id: TASK-327
title: 'Time grid: positions in ticks and one grid module (TM1)'
status: Done
assignee: []
created_date: '2026-11-23T19:52:00Z'
updated_date: '2026-11-24T03:24:00Z'
labels:
  - ux
  - bundle
milestone: m-15
dependencies:
  - TASK-325
references:
  - backlog/docs/designs/time-motions.md
  - architecture/decisions/0036-time-motions.md
priority: high
ordinal: 396000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/time-motions.md sections 2, 5, 8 (TM1). paw.timegrid with integer ticks (TPQ 61440), the grid setting (note value, t, bar, auto, frame, seconds, swing), lines that start again at each bar, folds and scopes; next, prev, floor, nearest, cell, steps, off. The cursor keeps a tick and want. The property test and the lint against grid arithmetic. Waits for the owner's answers on ADR 0036.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 paw.timegrid (Teal) owns the tick type (integer ticks, TPQ 61440), the grid setting (note value, t, bar, auto, frame, seconds, swing), lines(from, to), next, prev, floor, nearest, cell, steps and off; lines start again at each bar and follow meter changes, folds and scopes
- [ ] #2 The cursor modules keep a tick and want, never a column or a float beat; cursor.set_tick refuses a value with a fraction in tests; values from the kernel are rounded to a tick once, at the boundary
- [ ] #3 Property test tests/timegrid.lua (fixed seeds, no time) for the grids, meter maps, tempo maps, folds and scopes of design section 5 point 5: after next or prev the result is a line or a bound; n times next then n times prev gives the same tick; steps(steps(a, n), -n) == a; lines are integers, sorted and unique; zoom and scroll change no line
- [ ] #4 A lint run by the suite refuses opt.grid, opt.note_grid, util.round(.., grid) and / grid outside timegrid.tl, options.tl and the status line
- [ ] #5 Real-keys test: :grid 1/8t, :set swing=60, 999l then 999h gives the same tick, and each tick is an integer; no move changes its meaning in this bundle (TM2 does that)
- [ ] #6 The lua-testing skill and the API reference (tools/apidoc.lua) name paw.timegrid; Vale reports 0 alerts
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
PO 2026-11-23: criteria from backlog/docs/designs/time-motions.md sections 2, 5 and 8. Start after TASK-325 is merged (both change cursor.tl and the grid lines of arrange.tl) and after the owner accepts ADR 0036. If the owner answers Q5 or Q7 against the recommendation, change AC 1 or AC 2 before the start. Size M.

Facts from TASK-325 (report section 10): l/h/arrows go to cursor.right/left (defaults/keys.lua:248-251, defaults/cursor.lua:10-19) by count × paw.opt.grid from the current beat, now through paw.cursor.step (cursor.tl:347, exact k/n steps, offset kept); w/b/e/^/$ exact clip edges (cursor.lua:42-86); W/B bar starts; gP → cursor.snap(position) = util.round (cursor.tl:325, util.tl:139); set_beat clamps and applies cursor.over (folds.tl:481). Offset-keeping edits x + n*grid: clip.move/resize (defaults/clips.lua:431,438), > < shift (keys.lua:522-524), lane points (defaults/lanes.lua:309), insert steps (insert.tl:355), roll moves (keys.lua:677,1084-1097,1251-1254; roll_draw.tl:385,548,585). Snapping: quantize edit.tl:464-468; ruler click act/timeline.tl:134 via host.snap (frontend/host.tl:342); clip drag rounds the delta (act/clips.tl:363, arrange_mouse.tl:610); edge drags cursor.snap (arrange_mouse.tl:548,1187); grid click axis:step_at; notes notes.tl:45, controls.lua:71,217, act/notes.tl:265,487,554; tempo act/tempo.tl:24. Off-grid sources: take stop at the block (session/recording.rs:357-402), stretch.lua:229, Shift drags (1/64), window clicks, Ctrl-wheel √2 scroll, 1/3 and 1/10 grids. Floats: util.round, notes.snap, time.format (objects.tl:2184). TM1 no longer waits for TASK-325's design facts; it waits for the merge and the owner's ADR 0036 answers.

Built on branch worktree-agent-a2895d6ec15c4b267, commit 0bb44d9f (base 82f0aad0, 59 files). runtime/lua/paw/timegrid.tl (tick TPQ 61440, settings number, 1/N, 1/Nt, bar, auto, frame, s, ms; swing; lines over meter, folds, scope; lines/next/prev/floor/nearest/cell/steps/off/step/window). Arrange cursor keeps tick and want (set_tick, tick, want; cursor.bounds → timegrid.bounds; strict ticks in the suite). opt.grid/note_grid number|string, opt.swing new, contracts.Grid.label, paw.option.checks hook. tests/timegrid.lua (property tests), tests/gridlint.lua, tools/gridlint.lua + gridlint-allowed.txt (18 files). Bench grid_moves: about 1 ms a key (debug, loaded). Orchestrator decision: swing and bar restarts move h/l now (ADR 0036). After build: regenerate apidoc. Lands after batch 21.

PO 2026-11-24: built, waits to merge (batch 21 or 22); status In Progress until it is on main.

On local main in batches 21+22 (4300ace4, 2026-11-24, not pushed). Full suite passed after two fixes (cab47711 a plugin is not work in flight; 4300ace4 the pick test waits for the walk); nix flake check passed.
<!-- SECTION:NOTES:END -->
