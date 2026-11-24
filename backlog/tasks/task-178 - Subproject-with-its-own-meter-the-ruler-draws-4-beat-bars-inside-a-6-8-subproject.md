---
id: TASK-178
title: >-
  Subproject with its own meter: the ruler draws 4-beat bars inside a 6/8
  subproject
status: Done
assignee: []
created_date: '2026-11-22T23:46:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels: []
milestone: m-2
dependencies: []
priority: high
ordinal: 190000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-6.6 (2026-11-23). Inside a subproject made with :nest.new Bridge 8 6/8 meter=own (TASK-7.11), the ruler draws its bars 4 beats wide, while 3| goes to beat 6 (right for 6/8). The ruler must read the scope's own meter (paw.scope.own_time / nest_time) like the motions do.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Inside a meter=own 6/8 subproject the ruler marks a bar every 3 beats (6 eighths), by a golden screen or a screen test with real keys
- [ ] #2 The song's ruler outside stays 4/4
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed on branch worktree-agent-a4d1fef7eb87b9328 (holds TASK-6.6 merged; main merged). Commits 736b8346 (code+test), f3f49626 (docs, guide check, api.md). paw.time.lines (objects.tl) gives the bar/beat lines of the window's map; NestTime:lines (scope.tl) builds them for an own map from its bars and signatures (the kernel has no nest_tempo_lines). draw.bar_lines uses paw.time.lines, so the arrange ruler + grid and the piano roll/curve/plot rulers follow the scope. The status line's tempo/meter reads the window's time. Test: tests/nest.lua 'inside a meter=own 6/8 subproject, the ruler, the grid and the status line count 6/8; the song's stay 4/4' (real keys; fails on old code). Not changed: frontend.tl window state (GUI paused), the tempo lane of the arrange view, nest.tl meter_over (save a view inside an own-meter subproject).
<!-- SECTION:NOTES:END -->
