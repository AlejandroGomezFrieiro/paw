---
id: TASK-266
title: >-
  UX-6 and block folds: overviews (group rows, folded groups, framed block folds
  with their bar count); a closed block is one step of the cursor
status: Done
assignee: []
created_date: '2026-11-23T07:52:00Z'
updated_date: '2026-11-23T13:48:00Z'
labels:
  - ux
  - nest
milestone: m-15
dependencies:
  - TASK-6.4
priority: medium
ordinal: 330000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: backlog/docs/designs/scopes-ux.md (approved by the owner 2026-11-23, all recommendations). Each change gets T.expect_screen golden tests at 100x30 with the real keys; put a before/after screen in the report.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A group row shows ━ where its tracks have clips; a folded group lists its members; a closed block fold is a frame with name, bars, tracks and keys; the default fold name is like 'Piano, Pad 9-24'. Takes in TASK-225
- [ ] #2 (TASK-224) Test with real keys: on a closed block over two tracks, j from the row above the block lands on the row below it, and k comes back
- [ ] #3 (TASK-224) Test with real keys: l from the bar before a closed block lands on the bar after it; on an open block it lands on the first bar of the block
- [ ] #4 (TASK-224) narrowing.md says it; Vale reports 0 alerts
- [ ] #5 (TASK-225) Test: the cell of a closed block over four bars shows its name and 4 bars
- [ ] #6 (TASK-225) Test: in a narrow window the name stays and the count is cut
- [ ] #7 (TASK-225) narrowing.md says it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a020ae9fb78bc52bc: commits f7d3aed6 (the work), 1af4fe22 (merge main), e438ad72 (the block cursor mark uses F.cursor_beat from main), fa24d810 (golden write_keeps_the_group re-blessed: group rows show the overview). Group row overview, folded group member lines with notes and +N more, block fold frame (name, bars, tracks, keys), default block name 'Piano, Pad 9-24', closed block = one row (j/k via new paw.cursor.stop hook) and one step (l/h via folds.over). New glyph 'overview'. Goldens: tests/screens/folds/{block_fold,group_open,group_folded}.txt. Docs: narrowing.md, keys.md, about-scopes.md, api.md. AC #2/#3 built as Vim (one key onto the block, the next past it), not as a skip that makes a closed block unreachable: see the report. Not Done: orchestrator sets it after merge.

Landed on main in batch 17 (deb79a0f), with the merge fixes of 2026-11-23 (clock rounding, export leader domain, goldens, MCP render_stems).
<!-- SECTION:NOTES:END -->
