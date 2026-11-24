---
id: TASK-126
title: 'Teal wave 5, part 2: the piano roll'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels:
  - architecture
  - lua-review
milestone: m-2
dependencies:
  - TASK-125
priority: medium
ordinal: 138000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port `views/pianoroll.lua`, `roll_clips.lua`, `views/pianoroll_mouse.lua` and `views/pianoroll_strip.lua`. Export one record `PianoRoll`. Delete the 10 stand-in `Roll` and `PianoRoll` records. Split `view:render` (298 lines) by part.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L3 and its proposal P4.

Overlaps: TASK-22, TASK-113 (do not port while TASK-113 changes the file).
Dependencies: P3 is better first (the view reads `keymap`).

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 as P3, for these files
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Ported views/pianoroll, pianoroll_mouse, pianoroll_strip and roll_clips to Teal (3,701 lines of Teal from 2,427 of Lua). Branch worktree-agent-a1f9701320c340921, commit df7a0bbc (on main c386d3a4). paw.views.pianoroll returns a module record (types + view); roll_clips.Part is an interface. 10 Roll/PianoRoll stand-ins and their Layer/Part/RollClips/NoteMark/Tool stand-ins gone. render split by part; strip hooks view.strip instead of replacing render; init.lua loads roll_draw. any-allowed 54->53 lines (paw.roll_clips), Untyped in paw.d.tl 33->30. No test changed; scoped suites pass. Found, not fixed: :roll.tracks Enter does not update the line text (pick never passes the picker to the action).

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
