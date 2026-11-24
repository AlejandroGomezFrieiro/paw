---
id: TASK-6.7
title: 'Nest V7: keys in a scope stay under 100 ms'
status: Done
assignee: []
created_date: '2026-11-22T09:50:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels:
  - nest
  - performance
milestone: m-2
dependencies:
  - TASK-6.1
  - TASK-6.2
parent_task_id: TASK-6
priority: medium
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: prove that the keys stay fast in a scope on a large project, and fix what does not. This is V7 of nest.md.

What to do:
- Add a `scope` scenario (or a `--setup` for `keys`) to bench/profile/drive.py: bench/profile/project.lua with regions, entered with `znar` and `znag`.
- Measure each key: `znar`, `znn`, `zw`, `zW`, `]z`, `j` `k` `w` `b`, `zfar`, `zm`, `zr`, `:%quantize` in the scope, the piano roll opened in the scope.
- Each key stays under 100 ms of kernel time; a frame in a scope costs no more than a frame of the song. Fix each key over the limit, or make a ticket in m-3 for it.
- Write the numbers, with their spread, in bench/RESULTS.md.

Read first: bench/profile.md, bench/profile/drive.py, bench/RESULTS.md (2026-11-21 profile), AGENTS.md rule 7; the V3 and V4 commits (TASK-6.1, TASK-6.2).

Depends on: TASK-6.1, TASK-6.2 (it absorbed TASK-6.3).
Do not touch: other scenarios' numbers.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 bench/profile has a scenario for scopes that anyone can run
- [ ] #2 Each listed key takes less than 100 ms of kernel time on bench/profile/project.lua (median and spread in bench/RESULTS.md)
- [ ] #3 A frame in a scope costs no more than a frame of the song (numbers in bench/RESULTS.md)
- [ ] #4 Each key over the limit is fixed in this branch, or has a new ticket in m-3
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Slow keys found first (bench/profile/drive.py scope, shared binary 07a06cd3, 3 runs, load 6.3 to 8.2, measured under external load), kernel time per key:
- :%quantize in the region scope Verse B (16 bars x 64 tracks): 187 to 205 ms. Over the limit. The command quantize alone 76 to 136 ms, the job derived 23 to 63 ms.
- A frame of the whole screen in a region scope: 14.7 to 15.4 ms median, against 11.1 to 11.9 ms in the song. AC #3 fails: a frame in a scope costs more.
- j k w b in the region: 13 to 19 ms (the song: 7 to 12 ms in the 2026-11-21 profile), the same cause as the frame.
- All other keys under 100 ms: znar 38 to 48, znn 28 to 30, zw 8 to 26, ]z 30 to 39, zW 14 to 16, zfar 9 to 12, zm 32 to 76, zr 10 to 32, u after quantize 53 to 69, piano roll open 27 to 32, j in roll 34 to 41 (max 59), znag 26 to 28, j k in the group 9 to 12.

Done on branch worktree-agent-ac33aa51092d6a1a2, commit c210bbc2 (main 07a06cd3 merged, nothing new).
- bench/profile/drive.py scope: regions and a group added after the start (the project file stays), the keys of the ticket in order, a frame in the song, the region and the group. Documented in bench/profile.md.
- Fix 1, runtime/lua/paw/scope.tl: region() keeps the regions by id between reads (key: project edits and events sent, as ui.tl frame_stamp). Before, each lane and each ruler bar called paw.markers.list(), which read the whole project (21 % of a region frame). A frame in the region: 13 ms (main) to 11 ms, the same as the song (11 ms). j k b in the region: 14 to 16 ms to 10 to 12 ms.
- Fix 2, runtime/lua/paw/ex.tl M.items: the kernel gives only the notes that sound in the range (api.clip_notes with a range), not every note of every clip.
- Over the limit: :%quantize 1/4 (about 6 400 notes) 253 ms (225 to 262), first frame 76 ms; its u 92 ms (81 to 114). The cause is the chord reading after the frame (one slice of the job derived of 61 to 103 ms) and the command (45 to 58 ms), also in the song: TASK-183 in m-3.
- Numbers in bench/RESULTS.md (2026-11-23), 3 pairs, load 3.3 to 6.7, measured under external load.
- Tests: tests/scope.lua, a region scope follows its region when it gets longer and u; the quantize test has a note that sounds into the bridge from before it. TASK-77.8 can replace the region cache with its markers memo.
<!-- SECTION:NOTES:END -->
