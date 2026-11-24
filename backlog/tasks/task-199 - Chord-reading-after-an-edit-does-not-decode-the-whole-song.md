---
id: TASK-199
title: Chord reading after an edit does not decode the whole song
status: Done
assignee: []
created_date: '2026-11-23T02:43:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-3
dependencies: []
priority: medium
ordinal: 211000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-192 (2026-11-23): after :%quantize on Verse B, the chord reading job costs about 46 ms: 2,142 track windows, 256 groups and 32 mixes are made again, then the chords and keys of the whole song; about 15 ms is paw.derived's bookkeeping. Make the reading incremental: only the changed clips' windows are read again.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After an edit of one region, only the windows of the changed clips are made again (a test counts them)
- [ ] #2 Numbers in bench/RESULTS.md with their spread
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a0a2215499625cc36 (main b48920a4 + batch 8 b404646a). Commits 048be109 (code, test), 39f9e77b (bench/RESULTS.md). AC1: a window that only touches a changed clip at an edge is no longer made again (strict overlap, place end added up as read.part does, span cached per entry in paw.derived); after :%quantize in Verse B track windows 2176 -> 2048 (64x32), track bars 384 -> 256; tests/derived.lua counts 4x8 windows and 4 bars after :3quantize (fails on main). Also: derived reuses deps lists and skips source compare when unchanged; track windows read the step from the track value; track reads mute/clips as single fields. Allocation per reading 2.0 -> 1.47 MB, bytecodes 9.60 -> 8.79 M. Whole key: no measurable difference (medians 132/138/130 vs 141/128/121 ms). Finding: the whole-song decode and key path cost about 1 ms; the cost is derived bookkeeping (~half, mostly interpreted, recursive) and read.part, so incremental decode was not done.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
