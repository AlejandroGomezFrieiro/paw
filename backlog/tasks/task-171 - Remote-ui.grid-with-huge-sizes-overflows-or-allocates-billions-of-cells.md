---
id: TASK-171
title: 'Remote: ui.grid with huge sizes overflows or allocates billions of cells'
status: Done
assignee: []
created_date: '2026-11-22T22:47:00Z'
updated_date: '2026-11-23T02:44:00Z'
labels: []
milestone: m-12
dependencies: []
priority: high
ordinal: 183000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found and fixed by TASK-159 (branch worktree-agent-a2198b180004f31ef, 2026-11-23), with a regression test; Done when that branch is on main. remote::apply panicked or ran out of memory on w=h=i32::MAX or covered past i32::MAX. Surfaces are now held to MAX_CELLS. Test: a_surface_with_numbers_out_of_range_is_kept_within_the_screen.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Orchestrator 2026-11-23: the fix and its regression test are on main (b48920a4, batch 7); the batch's Rust tests pass.
<!-- SECTION:NOTES:END -->
