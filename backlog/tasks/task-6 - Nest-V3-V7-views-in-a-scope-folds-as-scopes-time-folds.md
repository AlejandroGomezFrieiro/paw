---
id: TASK-6
title: 'Nest V3-V7: views in a scope, folds as scopes, time folds'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-23T08:32:00Z'
labels:
  - nest
  - views
  - folds
  - epic
milestone: m-2
dependencies: []
priority: medium
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Epic. Do not build this ticket: build its children.

Nest V3-V7 (backlog/docs/designs/nest.md sections 3 and 5.1): views in a scope, folds as scopes, time folds, the picker and K, docs, a 100 ms benchmark. V1 and V2 (TASK-4) and R1, R2 (TASK-5) come before.

Children, in order:
- TASK-6.1: V3, views in a scope (M). Done.
- TASK-6.2: V4a and V4b, folds are view state, track folds per window, time folds and region folds by level, zm zr (M+M). It absorbed TASK-6.3 (owner, 2026-11-22).
- TASK-6.5: V5, K on a scope, folds in the picker (S).
- TASK-6.6: V6, about scopes and a how-to (S).
- TASK-6.7: V7, keys in a scope under 100 ms (S).
- TASK-6.4: V4c, block folds (S, low).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Split on 2026-11-22 into TASK-6.1 (V3), TASK-6.2 (V4a), TASK-6.3 (V4b), TASK-6.4 (V4c), TASK-6.5 (V5), TASK-6.6 (V6), TASK-6.7 (V7). Kept as an epic note: set it to Done when all children are merged.

Board review 2026-11-23: all children but TASK-6.4 (V4c block folds, low) are Done and on main (Merge TASK-6.5 e1fad312, TASK-6.6 25163ed3, TASK-6.7 a67225c3, TASK-6.2 5662f4d3). Set this epic to Done when TASK-6.4 merges.

PO 2026-11-23: TASK-224 (a closed block is one cursor step) is merged into TASK-266 (m-15), with TASK-225.

PO 2026-11-23 (after batch 14): TASK-6.4 merged in batch 14 (23350734). All children are Done; the epic is Done. The block-fold follow-ups are in TASK-266 (m-15).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Nest V3-V7 are on main: views in a scope, folds as view state, block folds, K on a scope, docs and the 100 ms bench (TASK-6.1, 6.2, 6.4, 6.5, 6.6, 6.7).
<!-- SECTION:FINAL_SUMMARY:END -->
