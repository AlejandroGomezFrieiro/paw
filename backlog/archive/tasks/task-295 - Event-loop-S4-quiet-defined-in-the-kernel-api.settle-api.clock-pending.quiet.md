---
id: TASK-295
title: >-
  Event loop S4: 'quiet' defined in the kernel (api.settle, api.clock,
  pending().quiet)
status: To Do
assignee: []
created_date: '2026-11-23T13:26:00Z'
updated_date: '2026-11-23T16:04:00Z'
labels:
  - event-loop
milestone: m-10
dependencies:
  - TASK-294
documentation:
  - backlog/docs/designs/event-loop-review.md
priority: medium
ordinal: 357000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design: event-loop-review.md, step S4. Delete from the runner working, busy, POLL_TURNS, the collector name and the now()==0 check.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23 (plan V2 bundles): Merged into TASK-294 (bundle EL2, architecture-plan.md 6.3): its step S4 is AC 6 of TASK-294.
<!-- SECTION:NOTES:END -->
