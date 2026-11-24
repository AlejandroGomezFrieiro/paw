---
id: TASK-11
title: 'Profile: live ticker backs off when frames do not change'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T05:20:00Z'
labels:
  - performance
milestone: m-3
dependencies: []
priority: high
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Idle with an armed input costs 6.7% CPU for 0.07 frames/s sent (ui.tl live ticker at 60 fps). Slow down after unchanged frames; end an audition poke when meters reach the floor. Size S. Source: bench/RESULTS.md 2026-11-21.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-aa182e32a1801f8ca. ui.tl ticker: after 20 live frames in a row with no changed cell it slows to 8/s; a poke ends at rest; idle-armed kernel 7.2% -> 5.0% (one reading each, loaded machine); record still 59 fps. Not unit-tested (suite has no attached terminal).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged 247293c9: ticker slows to 8 fps after 20 unchanged ticks; idle-armed 7.18% -> 4.98% kernel CPU (one run, load ~55); meters still at 59 fps with input.
<!-- SECTION:FINAL_SUMMARY:END -->
