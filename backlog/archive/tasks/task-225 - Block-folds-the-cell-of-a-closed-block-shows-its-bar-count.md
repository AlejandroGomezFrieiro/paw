---
id: TASK-225
title: 'Block folds: the cell of a closed block shows its bar count'
status: To Do
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - nest
  - folds
  - views
milestone: m-15
dependencies:
  - TASK-6.4
priority: low
ordinal: 253000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-6.4 (its agent named it). A closed track fold shows its name and how much it holds (for example `Fold 1 +3`). The cell of a closed block fold shows only its name, so the user cannot see how long it is.

What to build: the cell of a closed block fold shows the count of its bars after its name, in the same style as the other folds. When the cell is too narrow, the name stays and the count is cut first. The scene of the arrange view carries the text, so the window can draw it later.

Read first: runtime/lua/paw/views/arrange.tl (draw_block_folds and the text of the track folds and time folds), runtime/lua/paw/folds.tl, the TASK-6.4 commit 56b1e9de, tests/folds.lua, docs/reference/narrowing.md.

Depends on: TASK-6.4.
Do not touch: paw-gui (paused).

Size: XS.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: the cell of a closed block over four bars shows its name and 4 bars
- [ ] #2 Test: in a narrow window the name stays and the count is cut
- [ ] #3 narrowing.md says it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Taken in by TASK-266 (UX design).

Moved to m-15 with TASK-266, which takes it in.

PO 2026-11-23: merged into TASK-266 (owner: fewer, larger tickets). Its criteria and text are in TASK-266.
<!-- SECTION:NOTES:END -->
