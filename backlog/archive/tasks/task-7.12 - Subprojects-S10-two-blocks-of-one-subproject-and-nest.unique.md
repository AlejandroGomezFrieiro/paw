---
id: TASK-7.12
title: 'Subprojects S10: two blocks of one subproject, and :nest.unique'
status: To Do
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T12:38:00Z'
labels:
  - nest
  - subprojects
milestone: m-2
dependencies:
  - TASK-7.7
parent_task_id: TASK-7
priority: medium
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: one subproject placed twice (the breakdown at bar 49 and bar 97) is one subproject with two blocks: an edit inside is heard in both. `:nest.unique` separates one block.

User-visible behavior (nest.md 3.7, 4.5; Q3): `y` then `p` of a block pastes a linked block (the same nest). `:nest.unique` makes the block under the cursor a subproject of its own. `K` says `2 instances`. Promote of one block says `Ballad still plays at bar 97`.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7, 4.5, 3.9 (the last row). runtime/lua/paw/nest.tl, the register and paste code for clips (runtime/lua/paw/keymap.lua `setreg`, runtime/lua/paw/defaults/clips.lua); the S4 commit.

Depends on: TASK-7.7.
Do not touch: linked MIDI clips (TASK-85.x: another mechanism).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: y on a block, p at bar 97: an edit inside the subproject is heard in both blocks (render)
- [ ] #2 Test: :nest.unique on the second block, then an edit inside it does not change the first
- [ ] #3 Test: K says 2 instances; <Space>zp on one block gives the message that it still plays at the other
- [ ] #4 subprojects.md says it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Combined into TASK-7.11 (owner, 2026-11-22).
<!-- SECTION:NOTES:END -->
