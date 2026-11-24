---
id: TASK-386
title: >-
  Ruler rows and marks: one compositor places every row and mark of the ruler
  (as statuscolumn and extmarks)
status: In Progress
assignee: []
created_date: '2026-11-24T17:41:00Z'
updated_date: '2026-11-24T19:21:00Z'
labels:
  - design
  - ux
  - tui
  - agent:builder
milestone: m-15
dependencies: []
priority: medium
ordinal: 455000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-11-24 (after the misaligned meter marker of the ruler): the time axis and its columns follow the practice of Neovim's statuscolumn, with layers, so that each thing draws in its right layer. The owner accepted these answers:
1. One stack of layers and one compositor for every time view (arrange, piano roll, curve, utau's editor); each view chooses its layers.
2. A mark never moves from axis.x_of(time). Labels take the free cells next to their mark; where they collide the higher layer wins and the lower label is shortened, then dropped (a meter label wins over a bar number).
3. Layers are configurable as the part column is: paw.timeline.set(name, {order, hidden, glyphs, styles}); paw.ruler.add and paw.ruler.add_lane become layers of the same API.
4. The grid and the meter and section marks draw down through the part rows under the clips; the cursor and the playhead draw on top of all.
5. Order: the small fix of the ruler first (the invariant test of the time axis guards this rewrite); then a proposed ADR for the owner; the build goes after A2 and before B6.
Layers in their order: grid, bar numbers, clips (edges), sections, markers (meter, tempo, cues), selection, cursor, playhead. A layer gives marks (time, glyph, style, label, rows); only the compositor turns time into columns, so the zoomlint allow-list goes to near zero.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A proposed ADR, accepted by the owner, before any code
- [ ] #2 paw.ruler.row(name, spec), paw.marks.namespace, paw.marks.set/del/clear, paw.ruler.route and paw.ruler.set exist as ADR 0041 says; paw.ruler.add and paw.ruler.add_lane are gone (git grep); the meter and tempo marks, cues, regions, loop, punch, time selection and rulerplus use them
- [ ] #3 A visual test: the test project ruler-everything (meter changes, tempo changes, nested regions, cues, loop, punch, time selection, a time fold, a subproject scope, rulerplus with relativebar, the second ruler row and the tempo lane) has golden screens at three zoom levels and in a narrow window; the before screens (today's ruler) are in the report
- [ ] #4 The time axis test of TASK-385 runs on ruler-everything and passes: every sign is in the column of its time
- [ ] #5 K on a ruler column lists every mark there, with the labels that are not shown; a test with real keys
- [ ] #6 :ext.unload of an extension removes its rows and its namespaces; a test
- [ ] #7 Docs: the reference of paw.ruler and paw.marks, a how-to that adds a row and routes a namespace, and the rulerplus example on the new API; Vale 0
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
2026-11-24, owner: the design is accepted as ADR 0041 (architecture/decisions/0041-ruler-rows-and-marks.md), the hybrid of rows (as statuscolumn items, computed for the time in sight, ordered by the user's paw.opt.rulerrows) and marks (as extmarks, in a namespace per owner, row = name or over = name as ghost text, ranges as background). It replaces the layers-only answers 1 to 4 above where they differ. One compositor: a sign is always at axis.x_of(time); one sign per column per row by priority; labels are ghost text after the sign, joined by priority, names shortened with an ellipsis, numbers whole or dropped; K lists every mark of a column; the cursor and the playhead last, through all rows.

STATE 2026-11-24 (session paused): branch worktree-agent-adcf8552100a28494, head d312068b (931ac9c0 + UX fixes; screens in its target/report-evidence.md read well). OPEN: opus review running; the builder updates ADR 0044 draft (copied to architecture/decisions/0044-ruler-soft-signs-and-edges.md, status proposed: the OWNER must accept it). 2 ara tests fail on the branch (plugin archive, analysis): check with PAW_ARA_BRIDGE from nix build .#paw-ara. NEXT: review verdict, fixes, merge check (words ruler tempo meter zoom section time_axis describe guide), ff main. The skill line .claude/skills/paw-extension/SKILL.md:181 still shows paw.ruler.add: only the owner can edit .claude/skills (new text: paw.ruler.row("euclid", { after = "bars", marks = function(ctx) return {} end }) and paw.marks.set(paw.marks.namespace("euclid"), 32, { sign = "◆", label = "fill" }); models-table row 'bar labels' -> 'rows and marks of the ruler').
<!-- SECTION:NOTES:END -->
