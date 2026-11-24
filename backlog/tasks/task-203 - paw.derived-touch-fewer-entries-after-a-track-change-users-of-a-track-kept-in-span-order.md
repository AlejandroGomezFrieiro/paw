---
id: TASK-203
title: >-
  paw.derived: touch fewer entries after a track change (users of a track kept
  in span order)
status: Done
assignee: []
created_date: '2026-11-23T03:42:00Z'
updated_date: '2026-11-23T06:06:00Z'
labels: []
milestone: m-3
dependencies: []
priority: medium
ordinal: 215000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-200 (2026-11-23): the derived bookkeeping is compiled; its cost is the number of entries it touches. After :%quantize on Verse B about 2,950 entries go stale per reading, and push_over checks the span of each of the about 280 entries that read each of the 64 tracks (about 18,000 checks). Keep the users of a track in span order (or an interval index) so a change finds the overlapping entries without a check of each. Tools: scratchpad t200 (quant.lua, cmp.sh, drive.sh).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test counts the span checks after an edit of one region, and the count falls with the size of the change, not the number of users
- [ ] #2 Numbers in bench/RESULTS.md with their spread, measured under external load
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a4b2007f64daeac06 (on main d5127487), commit 4d2c0220 (derived.tl, tests/derived.lua, bench/RESULTS.md). An entry with touched (the tracks) keeps its users in a SpanIndex (by span start, with reach = latest end so far, plus a wide list for no or endless spans); push_over binary-searches the last span starting before the change's end and walks back while reach > from. The index goes on link of a new user, unlink, a new span in remake (the old deps), and a pass that stops before its end (users_epoch, stop_pass). Stats get checked (spans compared). AC1: new test in tests/derived.lua: after :3quantize on 2 tracks, 20 checks for 8 bars and for 32 bars, more for :3,6quantize; with a linear scan it gives 146/578 and fails. AC2: bench/RESULTS.md: span checks per reading 17984 -> 2368 (64x281 -> 64x37); entries made unchanged; reading medians lower in 10 of 10 pairs by 0.8-9.4 ms (~10%) but spreads overlap; whole key no measurable difference (106/106/102 vs 115/111/125 ms); load 2.5-6.4. Also moved the TASK-199 heading in RESULTS.md back over its own text (it sat above TASK-200's entry). Checks: tlcheck, fmtcheck, luacheck 0, apidoc check; suite only derived:, harmony, chord, key, roll pass with the shared binary.
<!-- SECTION:NOTES:END -->
