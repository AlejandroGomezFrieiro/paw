---
id: TASK-170
title: 'Clip reader: origin or note length near i64::MAX overflows the tick sums'
status: Done
assignee: []
created_date: '2026-11-22T22:47:00Z'
updated_date: '2026-11-23T02:44:00Z'
labels: []
milestone: m-12
dependencies: []
priority: medium
ordinal: 182000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found and fixed by TASK-159 (branch worktree-agent-a2198b180004f31ef, 2026-11-23), with a regression test; Done when that branch is on main. A .midi2 file whose paw: text gives an origin or a len near i64::MAX panics (dev) or gives wrong values (release). clipfile.rs tick sums now saturate. Test: an_origin_or_a_length_past_the_largest_tick_reads_without_a_panic.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Orchestrator 2026-11-23: the fix and its regression test are on main (b48920a4, batch 7); the batch's Rust tests pass.
<!-- SECTION:NOTES:END -->
