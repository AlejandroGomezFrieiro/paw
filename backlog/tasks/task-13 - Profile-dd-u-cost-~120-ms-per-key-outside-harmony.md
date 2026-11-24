---
id: TASK-13
title: 'Profile: dd/u cost ~120 ms per key outside harmony'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T09:45:00Z'
labels:
  - performance
milestone: m-3
dependencies: []
priority: high
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After HARMONY-FAST, dd,u still ~235 ms per round with the reading off. Profile with bench/profile drive.py repeat --keys dd,u --luaprof and fix to under 100 ms.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-adcd9b7c7b35844c6, commit 8d6194a4. Cause: device.removed had no track, harmony took nil as 'look at every track' (clip_list+hash of 2000 clips per dd/u); arrange dropped every mini roll and chain name on each change; qf plugins source asked device_get of all devices on device add/remove; bars loop of the reading did not pause. Fixed all four. Under load 10-13, 5 pairs: kernel per dd,u round 274 -> 192 ms, reading 151 -> 93 ms, longest reading slice 18 -> 7 ms, full frames 76 -> 58 ms; first frame dd 31 -> 15 ms, u 32 -> 13 ms. Left: re-weighing all windows after a whole-song track change (~45 ms/key, background slices).
<!-- SECTION:NOTES:END -->
