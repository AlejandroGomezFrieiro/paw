---
id: TASK-7.10
title: 'Subprojects S8: <Space>zW saves a view as a subproject with its own row'
status: To Do
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T12:38:00Z'
labels:
  - nest
  - subprojects
milestone: m-2
dependencies:
  - TASK-7.9
parent_task_id: TASK-7
priority: medium
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: `<Space>zW`, `:scope.write! [name]` saves a view as a subproject with its own row: the scope's clips, and copies of the devices and lanes of its tracks, move in, and one return row plays its mix.

What to build (nest.md 3.6, 3.7 table "a view → a subproject, its own row", 4.6 mix layout, 4.7):
- A group in the selection becomes a group inside the nest with its members.
- Routes at the boundary: a send to a bus that is also in the selection moves with it; a send to a bus outside becomes a send of the return row at the same level, and the message lists each such change; a side-chain from outside is refused with the route named (`Comp on Bass listens to Kick: take Kick in too, or use <Space>zw`).
- VCAs over moved tracks move to the return row, with a message.
- The 3.9 round trip: promote, then save again, gives the same project.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.6, 3.7, 3.9 ("Round trip"), 4.6, 4.7. runtime/lua/paw/nest.tl, runtime/lua/paw/routes.lua, runtime/lua/paw/vca.tl, runtime/lua/paw/groups.tl; the S7 commit.

Depends on: TASK-7.9.
Do not touch: own tempo (TASK-7.11).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: <Space>zW on two tracks with devices: one return row, the devices inside; the render before and after is the same
- [ ] #2 Test: a send to a bus outside becomes a send of the return row and the message names it; a side-chain from outside is refused with the route named
- [ ] #3 Test (the 3.9 round trip): a subproject with two tracks, regions, a lane on the return row and its own meter; <Space>zp then <Space>zW gives the same canonical project text with ids mapped, and the same render
- [ ] #4 subprojects.md says it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Combined into TASK-7.9 (owner, 2026-11-22).
<!-- SECTION:NOTES:END -->
