---
id: TASK-185
title: >-
  Inside a subproject: ruler tempo flags, :timesig, the tempo curve editor and
  :tempo.* still use song beats
status: Done
assignee: []
created_date: '2026-11-23T00:28:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-2
dependencies: []
priority: medium
ordinal: 197000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-182 (2026-11-23, branch worktree-agent-a1101608298901721). Inside a subproject: the tempo flags on the ruler (A.tempo_mark in the frontend) find the point in song beats while the ruler gives window beats, so a move or remove does nothing or changes a song point at the wrong beat; :timesig and the signature flags use song beats; the curve editor on paw://tempo edits the song's map in song beats; :tempo.ramp, :tempo.remove and :tempo.tap refuse inside a subproject with its own tempo. Route them through paw.tempolane (the rule of which map an edit changes) and paw.time. Starts after TASK-128 (frontend split) is on main.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each of these, inside a subproject with its own tempo or meter and inside one that follows the song, edits the right map at the right beat, by a test with real keys or mouse for each
- [ ] #2 One undo step each
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-ab2c22fec81cf4237, commit bc198fa5 (on c386d3a4). Inside a subproject, the ruler's tempo and signature flags (A.tempo_mark), :timesig, :timesig.remove, :tempo.ramp/.remove/.tap, :tempo and the curve editor of paw://tempo take window beats and go through paw.tempolane (the one place of the map rule; new: set_points, signature_set/move/remove, meter rule: own meter -> nest_set meter; own tempo + song meter -> the shown meter becomes own; else song map at paw.time.song_beat). paw.time.signature_points added; paw.tempo.marks uses paw.time. set_own and song_map_only removed. :tempo.tap resets when the clock goes back. Tests: tests/nest.lua (3, commands + curve editor, own/follow/own meter, one undo step each), tests/tuimouse.lua (1, ruler flags own/follow). No change in views/arrange*.lua. Kernel: nest_set meter exists, no Rust change.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
