---
id: TASK-183
title: >-
  An edit of thousands of notes: the chord reading runs in one slice of 60 to
  100 ms, and :%quantize costs 250 ms of kernel time
status: Done
assignee: []
created_date: '2026-11-23T00:18:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels:
  - performance
  - derived
milestone: m-3
dependencies: []
priority: medium
ordinal: 195000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-6.7 (bench/profile/drive.py scope). In the region scope Verse B of bench/profile/project.lua (16 bars, 64 tracks, about 6 400 notes), `:%quantize 1/4` takes 225 to 262 ms of kernel time, and the `u` after it 81 to 114 ms. The first frame comes after 76 ms (median). The key itself is fast enough for the user. The work after the frame is not.

Where the time goes (paw.opt.budget_ms names the callbacks, the Lua profiler gives the functions):
- The job derived runs one slice of 61 to 103 ms. harmony/song.lua make is one entry of the graph that reads every window through ctx:get, so the job cannot yield inside it (derived.lua ensure, remake, harmony/read.lua make).
- The command quantize itself: 45 to 58 ms. About a third is ex.tl M.items (api.clip_list for each track of the scope, api.clip_notes for each clip), and a third is objects.tl edit_notes.
- The same edit on the whole song costs more: this is not a cost of the scope.

Read first: backlog/docs/designs/derived.md, runtime/lua/paw/derived.tl, runtime/lua/paw/harmony/song.tl, runtime/lua/paw/ex.tl (M.items, M.apply), bench/RESULTS.md (2026-11-23: keys in a scope).

Measure with bench/profile/run.sh scope (and repeat --setup with the scope, --keys ':%quantize 1/4\r,u' --luaprof), against main at the time, with the spread, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No slice of the job derived takes more than 10 ms after :%quantize 1/4 in the scope Verse B (paw.opt.budget_ms = 10 names none)
- [ ] #2 :%quantize 1/4 and u in the scope each take less than 100 ms of kernel time (median and spread in bench/RESULTS.md)
- [ ] #3 A test counts the work (for example the windows the chord reading makes again), never the time
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a3515cae585801fdd (TASK-6.7 merged in; main merged at bc16df6d). Commits 69ecb6ac (code+tests), fb947f93 (merge of main: song.tl transpose key, objects.tl shift), dff94c2e (RESULTS.md, derived header, ex.md). derived.tl: eager nodes (track, tracks, span, step, bars made first; users marked only over touched time) and a pause before each make at any depth. song.tl: harmony.place (one clip by id) and harmony.drums. ex.tl: clip_list over the range, clips that do not meet the range are not read, apply sends only changed fields, :quantize skips notes on the grid and says so, start from the song beat. Numbers (15 keys, load 3.3-4.8): quantize 217 -> 135 ms, u 101 -> 74 ms. AC1: job derived over 10 ms in 2 of 25 quantize keys (13.8 ms max) - not fully met. AC2: u met, quantize not (frames, typing, ex.items, GC; TASK-184 tree_of). AC3: test in tests/derived.lua counts windows and entries a slice.
<!-- SECTION:NOTES:END -->
