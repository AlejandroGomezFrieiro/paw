---
id: TASK-114
title: 'Help index made at idle: slices of 13 to 68 ms'
status: Done
assignee: []
created_date: '2026-11-22T13:03:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels:
  - performance
milestone: m-3
dependencies: []
priority: medium
ordinal: 117000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-79 (paw.opt.budget_ms = 5, bench/profile/run.sh keys on project.lua, measured under external load, load average 70 to 94).

The budget check names 'a timer (paw/help.tl:1123)' at each start, 13 to 69 ms of wall time. runtime/lua/paw/help.tl M.prepare makes the index of help one second after the start, in slices of 4 ms (SLICE_MS). But build_now calls pause() only after each page. One md.parse of a large page (docs/reference/api.md), heading_tags and the tags loop run without a pause. A key that comes during the build waits for the slice.

Goal: each slice of the help index takes at most its 4 ms. Move the build to paw.slices (runtime/lua/paw/slices.tl, the job 'help'), and add pause points inside the long parts.

Read first: runtime/lua/paw/help.tl (build_now, M.prepare), runtime/lua/paw/slices.tl, docs/reference/lua-other.md (Long work in slices).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With budget_ms = 5, a start of paw with the large project writes no slow warning for the help index at a load average under 20
- [ ] #2 The index uses paw.slices (job help); tests/help.lua passes unchanged
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a25fe1714bde0f06c, commit 838eb364 (main fd0e1f0b merged, up to date). The help index is the job help of paw.slices (M.prepare returns the job); pauses inside md.parse (each line, table rows), md.render (blocks, table rows), heading_tags, the contents page, the code anchors, and a pausing merge sort of the tags. Line text joined once in fill. New test in tests/help.lua; bench/profile/help.lua; drive.py passes PAW_RUNTIME and LD_PRELOAD. Numbers in bench/RESULTS.md: slices over 5 ms 31-51 -> 7-19 (glibc), longest 17-37 -> 9-19 ms; with mimalloc (LD_PRELOAD) 2-3 slices over 5 ms, longest 5.7-6.9 ms. AC1 not fully met on glibc: perf puts 54% of the long slices in glibc malloc (malloc_consolidate); proposal: mimalloc as the global allocator of the paw binary (separate ticket). tests/search.lua 'regions, help tags, the Lua API' fails on main too (not this branch).
<!-- SECTION:NOTES:END -->
