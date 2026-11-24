---
id: TASK-293
title: >-
  Event loop S2: one clock rule (schedule clock for every 'when' in Rust) and a
  clock lint
status: To Do
assignee: []
created_date: '2026-11-23T13:26:00Z'
updated_date: '2026-11-23T16:04:00Z'
labels:
  - event-loop
milestone: m-10
dependencies:
  - TASK-292
documentation:
  - backlog/docs/designs/event-loop-review.md
priority: high
ordinal: 355000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: event-loop-review.md, step S2. Pass now into the polls; move the 10 Instant 'when' sites (undo sweep merge SWEEP_GAP, TOUCH_RELEASE, hash scan, read-ahead, audition end, progress throttles) to the schedule clock; a clocklint check. Delete 5 clock fields and their WallClock defaults.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23 (plan V2 bundles): Merged into TASK-292 (bundle EL1, architecture-plan.md 6.2): its step S2 is in the criteria of TASK-292.
<!-- SECTION:NOTES:END -->
