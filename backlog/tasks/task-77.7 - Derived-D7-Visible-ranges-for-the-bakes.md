---
id: TASK-77.7
title: 'Derived D7: Visible ranges for the bakes'
status: Done
assignee: []
created_date: '2026-11-22T15:23:00Z'
updated_date: '2026-11-23T00:46:00Z'
labels:
  - performance
  - derived
milestone: m-3
dependencies:
  - TASK-77.1
parent_task_id: TASK-77
priority: medium
ordinal: 126000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D7 of the derived-data design. Views tell their ranges (`paw.derived.visible`); the kernel gets the union (`api.view_ranges_set`); `bake_wants` gives `Priority::Visible`.

Read first: backlog/docs/designs/derived.md, part 4 (the design) and row D7 of part 5; part 2 (inventory) and part 3 (measurements) for the consumer.

Owner decisions (2026-11-22): the design is approved; Q1 no mark in the views (the status line shows the job only after 1 s, K on a chord says "reading"); Q2 paw.derived stays internal in D1 to D5 and becomes public in D6; Q3 no user option for memory, fixed limits per kind shown by :checkhealth derived.

Measure with the spread, on the bench project, against main at the time, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: Rust test: with all workers busy on Background bakes, a bake in a visible range starts first. Lua test: a view drawn tells its range.
- [ ] #2 Number to meet: With 20 Background stretch bakes waiting, the first visible bake starts within `SETTLE` (150 ms) and one poll.
- [ ] #3 Docs follow the change; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Views tell their ranges: arrange calls paw.derived.visible(window, from, to, tracks) as it draws; ui.render brackets each frame (derived.frame_start/frame_end), and frame_end sends the ranges to the kernel when they changed (api.view_ranges_set; api.view_ranges reads them, listed by :checkhealth derived). Rust: stretched::ViewRange + Upkeep.views; bake_wants gives Priority::Visible to a clip in a shown range on a shown track; the scheduler lets Visible (and Playing) preempt the oldest Background bake. Docs: reference/stretch.md, api.md. Generated api.d.tl/paw.lua/api.md lines written by hand (shared binary lacks the functions): run apidoc after the build. Window part: none needed (paw-gui untouched). Branch worktree-agent-ad4ed1d05c488ef19, commit 7d463570.
<!-- SECTION:NOTES:END -->
