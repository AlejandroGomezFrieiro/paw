---
id: TASK-296
title: >-
  Event loop S5: an honest stepped backend (reports Step, no sticky null_steps,
  no 500 ms wait)
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
ordinal: 358000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: event-loop-review.md, step S5. The backend reports Step; null_steps goes; suite.sh passes --audio step; the 500 ms wait of :engine threads= goes; wait_blocks fails loudly when not stepped. Confirm the paused window still builds in principle (StreamInfo), without building it.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23 (plan V2 bundles): Merged into TASK-292 (bundle EL1, architecture-plan.md 6.2): its step S5 is in the criteria of TASK-292.
<!-- SECTION:NOTES:END -->
