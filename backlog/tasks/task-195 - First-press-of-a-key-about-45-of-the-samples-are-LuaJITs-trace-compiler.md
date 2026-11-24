---
id: TASK-195
title: 'First press of a key: about 45 % of the samples are LuaJIT''s trace compiler'
status: Done
assignee: []
created_date: '2026-11-23T02:14:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels: []
milestone: m-3
dependencies: []
priority: low
ordinal: 207000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-190 (2026-11-23, bench/profile --luaprof on the scope scenario): in each first-time key, about 45 % of the jit.profile samples are in VM state J (the trace compiler), on main and on the branch. This is the larger cost of the first press of any key. Look at what compiles (jit.v or jit.dump on one key), whether jit.opt (hotloop, hotexit, maxtrace) or a warm-up after startup lowers it, and what it costs at startup. Measured under external load, with spread.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The cost of the trace compiler on a first key is measured and explained in bench/RESULTS.md
- [x] #2 A change is made only if it lowers the first-key cost without raising startup or repeated keys beyond the spread
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done on branch worktree-agent-a47fec7df5580ae41, commit 00155433 (merged with main 8e91e5b0, up to date). Cause: LuaJIT's trace cache (maxtrace 1000) filled during the start and 2-3 times during the scope scenario; each flush recompiled all hot code. Part of the 45 % was the --luaprof probe itself (jit.profile start/stop flush all traces). Change: runtime/lua/paw/jit.tl sets maxtrace=8000, maxmcode=16384 before the runtime loads (required first by paw/init.lua). scope first keys 446-535 -> 325-416 ms; traces started 2991-4164 -> 1131-1256; flushes 2-3 -> 0; trace compiler share (perf, --vmstates) 33-41 % -> 15-25 %; repeated :%quantize 93-116 -> 45-54 ms; j/k and startup no measurable change; RSS after start +1 MB, 2.4 MB machine code after 4 scope rounds. hotloop=200 and hotexit=40 did not help. drive.py: per-key 'traces' counts in scope, and --vmstates (perf cycles by LuaJIT part). bench/RESULTS.md and bench/profile.md updated.

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
