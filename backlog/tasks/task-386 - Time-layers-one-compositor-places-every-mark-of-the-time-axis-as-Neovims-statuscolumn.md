---
id: TASK-386
title: >-
  Time layers: one compositor places every mark of the time axis, as Neovim's
  statuscolumn
status: To Do
assignee: []
created_date: '2026-11-24T17:41:00Z'
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
