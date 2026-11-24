---
id: TASK-226
title: >-
  Bug: inside a subproject the ruler draws the song's regions from bar 1, and
  the status line shows a negative bar
status: Done
assignee: []
created_date: '2026-11-23T07:10:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - bug
milestone: m-2
dependencies: []
priority: high
ordinal: 267000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen 2026-11-23 in a sealed screen run (scratchpad screens/shots.lua, batch 14 build). Inside the subproject Bridge (song bars 9-16, which is the region Verse), the region row of the ruler shows 'Intro' at the subproject's bar 1 and 'Verse' at bar 9; inside Fill (song bars 17-18, region Chorus) it shows 'Intro' too. The song's regions are drawn without the block's offset. The status line cursor reads '-7.1.00' inside Bridge (the song-time offset applied the wrong way), while the scope part says '1.2 (9.2)'. Narrowed to a region (Verse), the ruler's bar numbers mix the scope's bars (1, 3, 5) and song bars (11, 12, 13).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Inside a subproject, the region row shows the regions that the block covers, at their place in the subproject, or none when the subproject follows no regions (decide which and say so in subprojects.md)
- [x] #2 The status line cursor inside a subproject shows the subproject's bar and the song bar, never a negative bar
- [x] #3 In a scope of a region, the ruler uses one numbering (the design says which), and a golden screen test guards it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed on branch worktree-agent-a47c4593c0b5adfd8, commit f6e9dcdb. Ruler in a scope: one numbering (scope bars); scopebars loses 'both', default 'local'; song bar only in the status line and K. Regions lane: song regions placed in window time (local_beat) and cut to the scope's time (paw.markers.placed, paw.ruler.lane_time); mouse uses the same. Status playhead: scope bars inside the scope time, '@<song place>' outside (no negative bar). paw.scope.song_offset sums the nest chain: nested subproject shows the song bar (1.1 (11.1)), regions and loop at the right place. Goldens: tests/screens/scope/region_scope.txt, tests/screens/nest/subproject_regions.txt, nested_subproject_regions.txt. Docs: narrowing.md, subprojects.md, options.md, status-line.md, two how-tos. Not fixed (other cause): in a split, a window inside a subproject that is not current scrolls by the shared cursor of the other timeline; dragging a region inside a subproject writes a window beat.

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
