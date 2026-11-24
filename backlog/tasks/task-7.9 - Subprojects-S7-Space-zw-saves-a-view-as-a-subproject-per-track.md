---
id: TASK-7.9
title: 'Subprojects S7-S8: <Space>zw and <Space>zW save a view as a subproject'
status: Done
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T20:23:00Z'
labels:
  - nest
  - subprojects
milestone: m-2
dependencies:
  - TASK-7.6
  - TASK-7.2
parent_task_id: TASK-7
priority: medium
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Combined ticket (owner, 2026-11-22): one agent builds TASK-7.9, TASK-7.10 in order, with one build, one suite run and one merge. Commit after each part.

Goal: `<Space>zw`, `:scope.write [name]` saves a view as a subproject, per track: the scope's clips move into a nest, the song gets blocks on the rows they came from, and the song sounds the same to the sample. This is the pass mode of nest.md 4.4.

What to build (nest.md 3.6, 4.4 "Per track, pass mode", 4.6 `make`; Q2, Q4, Q7):
- `paw.nest.make(region, opts)` per track: a nest track for each row with clips in the range, the clips cut at the edges and moved in, shifted; the meter of a time scope copied as the nest's own; markers and regions inside move in, the region that is the range stays in the song; on each row a nest clip with `play` = its nest track. One undo step. Message: `nested 4 tracks, bars 17-24, as Bridge (6/8)`.
- Pass mode playback: a nest track with no devices, unity fader and pan and no lanes has no sound of its own, so sync places its clips (mapped and cut) as regions on the host row: they play through the host's devices.
- `.` repeats `<Space>zw` on the next block.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.6, 4.4, 4.6, 4.7 (per track crosses nothing). runtime/lua/paw/nest.tl, crates/paw-core/src/sync/clips.rs; the S2a, S2b and S6 commits.

Depends on: TASK-7.8, TASK-7.2.
Do not touch: the own-row save (TASK-7.10).

Size: M.

## Part of TASK-7.10: Subprojects S8: <Space>zW saves a view as a subproject with its own row

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
- [ ] #1 (7.9) Test with real keys: znar in Bridge, then <Space>zw: blocks on the rows the clips came from; a render before and after is bit-identical
- [ ] #2 (7.9) Test: <Space>zw, then <Space>zp gives the same canonical project text (ids mapped)
- [ ] #3 (7.9) Test: the meter of the range is the nest's own; markers inside moved in; the region that is the range stayed in the song
- [ ] #4 (7.9) Test: u restores the project before <Space>zw
- [ ] #5 (7.9) subprojects.md and keys.md say it; Vale 0 errors
- [ ] #6 (7.10) Test with real keys: <Space>zW on two tracks with devices: one return row, the devices inside; the render before and after is the same
- [ ] #7 (7.10) Test: a send to a bus outside becomes a send of the return row and the message names it; a side-chain from outside is refused with the route named
- [ ] #8 (7.10) Test (the 3.9 round trip): a subproject with two tracks, regions, a lane on the return row and its own meter; <Space>zp then <Space>zW gives the same canonical project text with ids mapped, and the same render
- [ ] #9 (7.10) subprojects.md says it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-7.9 + TASK-7.10 built on branch worktree-agent-a7723bb3bb3161d78 (worktree .claude/worktrees/agent-a7723bb3bb3161d78). Commits: 76cbc317 (S7-S8: <Space>zw / :scope.write [name], <Space>zW / :scope.write! [name]; Session::nest_save in session/save.rs, pass-mode playback in sync/nests.rs, promote of a per-track save), e6ad5cd7 (:scope.write refuses a word with '/': it is a path, kept for TASK-7.14 :scope.write <folder>; test and subprojects.md line), merges of main 84e6bd04, b7537bfb, 3ab2c29e. All 9 acceptance criteria have tests in tests/nest.lua; docs: subprojects.md, keys.md, narrowing.md, limits.md, api.md. Full suite before the last main merge: 1 failure, a notation speed test under load (105 ms against 101 ms, slowdown 3.4), not in this branch's files. At the merge: cargo test -p paw-core, suite only nest, the full suite. Not Done.

Merged to main in 7ae25570 (batch 1, 2026-11-22): dev build, full suite with plugins passed, nextest paw-core/paw-scene passed.
<!-- SECTION:NOTES:END -->
