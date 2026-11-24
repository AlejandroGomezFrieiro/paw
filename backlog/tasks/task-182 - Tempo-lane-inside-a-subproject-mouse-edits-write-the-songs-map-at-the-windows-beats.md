---
id: TASK-182
title: >-
  Tempo lane inside a subproject: mouse edits write the song's map at the
  window's beats
status: Done
assignee: []
created_date: '2026-11-23T00:18:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels: []
milestone: m-2
dependencies: []
priority: high
ordinal: 194000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-181 (2026-11-23, branch worktree-agent-a5e4a508eb3b558cf). The tempo lane inside a subproject now draws the window's tempo (paw.time.tempo_points), but mouse edits and lane keys still write the song's tempo map at the window's beats: the song's tempo changes at the wrong place. Inside a subproject with its own tempo, an edit must write its own map; inside one that follows the song, the song's map at the song's beat (paw.time.song_beat). One undo step each.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Inside a subproject with its own tempo, a tempo point made on the lane is in its own map and the song's map stays the same, by a test with real keys or mouse
- [ ] #2 Inside a subproject that follows the song, the point lands at the song's beat of the cursor
- [ ] #3 u takes each edit back in one step
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a1101608298901721, commit 748e8930 (on top of TASK-181's branch worktree-agent-a5e4a508eb3b558cf, merged first). paw.tempolane edits the window's map: own tempo -> nest_set(tempo own points), one undo step; follow -> song map at paw.time.song_beat. add/move/remove/ramp/draw, :tempo.move, grt, and the arrange mouse's lane hit list use it. frontend.tl: one line (tempo_lane payload uses paw.tempolane.points). Tests: tuimouse (own: click in own map, song map same, u; follow: click at song beat 24, drag, u per step), nest (grt own tempo, u). Left: ruler flags (A.tempo_mark) and :timesig still use song beats inside a subproject; curve editor paw://tempo is the song's map.

Orchestrator: at the merge after TASK-128's split, carry the one frontend.tl line (project.tempo_lane.points = paw.tempolane.points()) into the split file. Follow-up: TASK-185.
<!-- SECTION:NOTES:END -->
