---
id: TASK-224
title: 'Block folds: a closed block is one step of the cursor'
status: To Do
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - nest
  - folds
  - keys
milestone: m-2
dependencies:
  - TASK-6.4
priority: low
ordinal: 252000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-6.4 (its agent named it). A closed block fold draws one cell over its tracks and bars. The cursor still moves through the rows and the bars under the cell one at a time, as if the block was open. In Vim a closed fold is one line for the motions.

What to build: in the arrange view, with a closed block fold, `j` and `k` go past all the rows of the block in one step, and `l` and `h` go past its bars in one step. The other motions across time treat the block as one bar. The other tracks at that time move as usual. An open block changes nothing.

Read first: runtime/lua/paw/folds.tl (is_block, blocks, block_at_cursor), runtime/lua/paw/views/arrange.tl (draw_block_folds and the cursor motions), the TASK-6.4 commit 56b1e9de, tests/folds.lua, docs/reference/narrowing.md (Block folds), docs/reference/key-rule.md.

Depends on: TASK-6.4.
Do not touch: the engine; the time folds and track folds.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: on a closed block over two tracks, j from the row above the block lands on the row below it, and k comes back
- [ ] #2 Test with real keys: l from the bar before a closed block lands on the bar after it; on an open block it lands on the first bar of the block
- [ ] #3 narrowing.md says it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-266 (owner: fewer, larger tickets). Its criteria and text are in TASK-266.
<!-- SECTION:NOTES:END -->
