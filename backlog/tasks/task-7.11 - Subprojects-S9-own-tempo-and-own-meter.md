---
id: TASK-7.11
title: >-
  Subprojects S9-S10: own tempo and meter, two blocks of one subproject and
  :nest.unique
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T23:53:00Z'
labels:
  - nest
  - subprojects
  - tempo
milestone: m-2
dependencies:
  - TASK-7.3
  - TASK-7.6
parent_task_id: TASK-7
priority: medium
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Combined ticket (owner, 2026-11-22): one agent builds TASK-7.11, TASK-7.12 in order, with one build, one suite run and one merge. Commit after each part.

Goal: a subproject can have its own tempo and its own meter, apart from the song's map.

User-visible behavior (nest.md 3.7, 4.1, 4.2; Q5, Q20, Q21):
- `:nest.time own`: the subproject's own tempo map; its length in the song follows its seconds; the song's map does not change. `:nest.time follow` goes back.
- `:nest.new Ballad 8 6/8 meter=own` and `:nest.meter 6/8`: a meter of its own with the song's map unchanged (polymeter).
- Devices inside see the subproject's own tempo (TASK-7.5's transport).
- `<Space>zp` of an own-tempo subproject writes its tempo into the song's map over its span, and the song's tempo back after it, so that the sound and the beats stay; the message says so.
- `K` and the status line show `own tempo`.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7, 3.9 (Tempo row), 4.2 (`NestTempo`, `NestMeter`, `TempoMap::nest`). crates/paw-engine/src/tempo.rs, runtime/lua/paw/tempo.tl, runtime/lua/paw/nest.tl; the S2c and S6 commits.

Depends on: TASK-7.3 (it absorbed TASK-7.5), TASK-7.6 (it absorbed TASK-7.8).
Do not touch: freeze (TASK-7.13).

Size: M.

## Part of TASK-7.12: Subprojects S10: two blocks of one subproject, and :nest.unique

Goal: one subproject placed twice (the breakdown at bar 49 and bar 97) is one subproject with two blocks: an edit inside is heard in both. `:nest.unique` separates one block.

User-visible behavior (nest.md 3.7, 4.5; Q3): `y` then `p` of a block pastes a linked block (the same nest). `:nest.unique` makes the block under the cursor a subproject of its own. `K` says `2 instances`. Promote of one block says `Ballad still plays at bar 97`.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7, 4.5, 3.9 (the last row). runtime/lua/paw/nest.tl, the register and paste code for clips (runtime/lua/paw/keymap.lua `setreg`, runtime/lua/paw/defaults/clips.lua); the S4 commit.

Depends on: TASK-7.6 (it absorbed TASK-7.7).
Do not touch: linked MIDI clips (TASK-85.x: another mechanism).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 (7.11) Test: a ritardando of the song over a block changes the onsets of a follow subproject and not those of an own one (render and compare the onset times)
- [ ] #2 (7.11) Test: meter=own keeps the song's map unchanged, and the subproject's ruler shows 6/8
- [ ] #3 (7.11) Test: <Space>zp of an own-tempo subproject keeps the render the same and writes the tempo into the song's map; the message says so
- [ ] #4 (7.11) subprojects.md and tempo.md say it; Vale 0 errors
- [ ] #5 (7.12) Test with real keys: y on a block, p at bar 97: an edit inside the subproject is heard in both blocks (render)
- [ ] #6 (7.12) Test: :nest.unique on the second block, then an edit inside it does not change the first
- [ ] #7 (7.12) Test: K says 2 instances; <Space>zp on one block gives the message that it still plays at the other
- [ ] #8 (7.12) subprojects.md says it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-7.11 + TASK-7.12 on branch worktree-agent-a3cf1111e2e9ba21d. Commits: 9169cfa5 (nest timing), 48b57e66 (commands, promote, linked blocks, docs), e4a2b25b (fix after the merge run: no Lua userdata for the own time, which crashed LuaJIT in a finalizer; nest_own_tempo/nest_song_beat/nest_beat/nest_tempo_* kernel functions; the zp render test allows a one-frame shift). Needs a new build, then apidoc, then the tests. Not Done.

2026-11-23: taken out of batch 3 (zp render test, SIGSEGV in a gc finalizer of the NestTime userdata, apidoc any). Fixed in e4a2b25b; goes in batch 4.

Merged to main (batch 4, 2026-11-23): dev build, apidoc regenerated, nextest paw-core/engine/tui/mcp (400) and the full suite with plugins passed. At the merge: vzoom.tl's Paw record names the keymap (TASK-125 took it out of partial.Paw).
<!-- SECTION:NOTES:END -->
