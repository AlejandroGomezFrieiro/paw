---
id: TASK-7.7
title: 'Subprojects S4-S5: the return row, blocks, K, :nest.list and stems'
status: To Do
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T12:38:00Z'
labels:
  - nest
  - subprojects
  - views
milestone: m-2
dependencies:
  - TASK-7.6
parent_task_id: TASK-7
priority: medium
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the user sees and mixes a subproject in the song: its blocks on its return row, its tracks in place, a description, a list, and stems when he wants them. Parts S4 and S5 of nest.md.

User-visible behavior (nest.md 3.7, 4.5, 4.8; Q23):
- The arrange view draws each block on the return row: a frame, the name once, a `⧉` mark, and a small view of what plays.
- `za` on the return row opens the subproject's tracks under it, in place, in the song's time. Edits there are edits of the subproject.
- `K` on a block: `nest Ballad · 6/8 · 8 bars · follows the tempo · 2 tracks · 1 instance · live`.
- `:nest.list`: the subprojects, their blocks and the unused ones; choose one to enter it.
- `:nest.outputs stems`: one return row for each subproject track, in a group under the subproject's row, made and named by the command. `:nest.outputs master` goes back to one row. One undo step each.
- The window frontend draws the same scene.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7, 4.5, 4.8. runtime/lua/paw/views/arrange.lua (clip drawing), runtime/lua/paw/groups.tl (a fold in place), tests/arrange_scene.lua, the paw-gui arrange drawing; the S3 commit.

Depends on: TASK-7.6.
Do not touch: promote (TASK-7.8).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: the block is drawn with its frame, name and ⧉ in the terminal and in the scene (tests/arrange_scene.lua, paw-gui tests)
- [ ] #2 Test with real keys: za on the return row shows the subproject's tracks under it; an edit there changes the subproject
- [ ] #3 Test: K on a block gives the text above
- [ ] #4 Test: :nest.outputs stems makes a row for each track; the sum of the stems renders as the stereo return did; :nest.outputs master and u restore
- [ ] #5 subprojects.md and keys.md say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Combined into TASK-7.6 (owner, 2026-11-22).
<!-- SECTION:NOTES:END -->
