---
id: TASK-172
title: paw-scene write_text overflows at column i32::MAX
status: Done
assignee: []
created_date: '2026-11-22T22:47:00Z'
updated_date: '2026-11-23T02:44:00Z'
labels: []
milestone: m-12
dependencies: []
priority: medium
ordinal: 184000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found and fixed by TASK-159 (branch worktree-agent-a2198b180004f31ef, 2026-11-23), with a regression test; Done when that branch is on main. Column sums now saturate. Test: text_at_the_last_column_of_i32_is_off_the_screen. Internal change; the paused window should still build.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Orchestrator 2026-11-23: the fix and its regression test are on main (b48920a4, batch 7); the batch's Rust tests pass.
<!-- SECTION:NOTES:END -->
