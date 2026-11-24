---
id: TASK-77.6
title: 'Derived D6: Notation (the first extension consumer)'
status: To Do
assignee: []
created_date: '2026-11-22T15:23:00Z'
updated_date: '2026-11-23T06:12:00Z'
labels:
  - performance
  - derived
milestone: m-3
dependencies:
  - TASK-77.1
parent_task_id: TASK-77
priority: medium
ordinal: 125000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D6 of the derived-data design. The measure memo, the layout cache and the score of parts move to `paw.derived` nodes; the first layout of a large clip runs in slices. The API becomes public here (owner question Q2).

Read first: backlog/docs/designs/derived.md, part 4 (the design) and row D6 of part 5; part 2 (inventory) and part 3 (measurements) for the consumer.

Owner decisions (2026-11-22): the design is approved; Q1 no mark in the views (the status line shows the job only after 1 s, K on a chord says "reading"); Q2 paw.derived stays internal in D1 to D5 and becomes public in D6; Q3 no user option for memory, fixed limits per kind shown by :checkhealth derived.

Measure with the spread, on the bench project, against main at the time, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: The notation tests pass unchanged. An edit of one measure makes one measure (`M.stats.measures` + 1).
- [ ] #2 Number to meet: Notation frame after a note edit: 1.5 times a frame after a move or less (9.4 to 10.4 ms today).
- [ ] #3 Docs follow the change; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board review 2026-11-23: archived. Its plan conflicts with a later owner decision: notation moves to Rust as a native extension (m-11, TASK-135 to TASK-139), not further work on the Lua notation. Work on the Lua memo and layout cache of notation is lost when the port comes. The idea (a measure memo, a layout cache, a first layout in slices) goes to the Rust notation design as a note on TASK-135. Owner question Q2 (paw.derived public) waits for a consumer outside the runtime; no extension needs it now.
<!-- SECTION:NOTES:END -->
