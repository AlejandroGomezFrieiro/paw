---
id: TASK-77.3
title: 'Derived D3: The search index'
status: Done
assignee: []
created_date: '2026-11-22T15:23:00Z'
updated_date: '2026-11-22T20:23:00Z'
labels:
  - performance
  - derived
milestone: m-3
dependencies:
  - TASK-77.1
parent_task_id: TASK-77
priority: medium
ordinal: 122000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D3 of the derived-data design. The records of `paw.grep` and the fields that `paw.query` reads become a family with clip content (and track, marker, device fields) as the key, made in background slices; `:vimgrep` and the query read the join.

Read first: backlog/docs/designs/derived.md, part 4 (the design) and row D3 of part 5; part 2 (inventory) and part 3 (measurements) for the consumer.

Owner decisions (2026-11-22): the design is approved; Q1 no mark in the views (the status line shows the job only after 1 s, K on a chord says "reading"); Q2 paw.derived stays internal in D1 to D5 and becomes public in D6; Q3 no user option for memory, fixed limits per kind shown by :checkhealth derived.

Measure with the spread, on the bench project, against main at the time, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: After an edit of one clip, a second `:vimgrep` makes the records of that clip only (`stats().made` = 1). The search tests pass unchanged.
- [ ] #2 Number to meet: Second `:vimgrep /pizz/` after one edit: 10 ms or less (37 to 91 ms today). `note[pitch>=c6]`: 20 ms or less (81 to 196 ms today).
- [ ] #3 Docs follow the change; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-ac2c47ba0370cf9ae (head 4cfd8b92; commits d347c404 index, 653fd39b numbers, fix 'one_line' for the strict tl check, merges of main up to e770d109). paw.query nodes of clips and notes (paw/query/tree.tl) and paw.grep records of tracks and clips are paw.derived families; after an edit only the edited clip is made again (tests/search.lua, stats().made = 1). Numbers (bench/RESULTS.md, 5 pairs, measured under external load, load 49-59): second :vimgrep /pizz/ 2.6-11.1 ms (p50 3.0-5.4) vs main 38-101; note[pitch>=c6] 10.2-20.1 ms (p50 11.0-18.9) vs main 94-232. The p50 values meet the targets; the worst single rounds under load are 1.1 ms and 0.1 ms above them. Cost: index keeps 31.7 MB Lua heap on the bench project; first search 142 ms (main 59). Docs: grep.md, queries.md, api.md. Not Done.

Merged to main in 7ae25570 (batch 1, 2026-11-22): dev build, full suite with plugins passed, nextest paw-core/paw-scene passed.
<!-- SECTION:NOTES:END -->
