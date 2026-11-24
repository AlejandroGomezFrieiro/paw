---
id: TASK-14
title: 'Profile: full frame 7-12 ms (clip_list JSON every frame)'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T09:53:00Z'
labels:
  - performance
  - ui
milestone: m-3
dependencies: []
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
clip_list called 17x per frame, SipHash of notes and stat of files per frame, JSON + to_lua. Cache note stamps, file events for offline checks, lean clip list for views. Size M.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-adcd9b7c7b35844c6, commit f13101d1. Notes::stamp cached (OnceLock cleared by each &mut method); clip_list/clip_get/cue_list serialize a typed ClipView straight to Lua (no serde_json map, None fields skipped). clip_list of 64 tracks 7.7 -> 3.1 ms; full arrange frame 73M -> 59M instructions (5 pairs), 14.5 -> 13.5 ms kernel under load 39-55. Offline stat per audio clip kept: inotify misses renames of parent folders (would report a missing file as present). Rest of a frame is the Lua drawing of roles.
<!-- SECTION:NOTES:END -->
