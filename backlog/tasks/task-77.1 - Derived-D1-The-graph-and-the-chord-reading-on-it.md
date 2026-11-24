---
id: TASK-77.1
title: 'Derived D1: The graph, and the chord reading on it'
status: Done
assignee: []
created_date: '2026-11-22T15:23:00Z'
updated_date: '2026-11-22T17:50:00Z'
labels:
  - performance
  - derived
milestone: m-3
dependencies: []
parent_task_id: TASK-77
priority: high
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D1 of the derived-data design. `paw.derived` (`derived.tl`): node types, keys, the reverse index, the `derived` slices job, priorities, `derived.changed`, `:checkhealth derived`. Kernel: `fields` in `track.changed`, `stamp` in clip events, `tempo_stamp`. `harmony/song.tl` becomes the nodes of 4.11.

Read first: backlog/docs/designs/derived.md, part 4 (the design) and row D1 of part 5; part 2 (inventory) and part 3 (measurements) for the consumer.

Owner decisions (2026-11-22): the design is approved; Q1 no mark in the views (the status line shows the job only after 1 s, K on a chord says "reading"); Q2 paw.derived stays internal in D1 to D5 and becomes public in D6; Q3 no user option for memory, fixed limits per kind shown by :checkhealth derived.

Measure with the spread, on the bench project, against main at the time, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: (a) After 300 random note sets with 6 random edits each, the reading equals a reading of all notes at once (the HARMONY-FAST check). (b) A mute of a track that spans the song makes no `harmony.track_window` node of another track (`stats().made`). (c) A change of a track's volume reads nothing. (d) `tests/harmony.lua` passes unchanged.
- [ ] #2 Number to meet: Reading after a mute: 10 ms or less of processor time (28 to 46 ms today, load 8 to 16), and a third of today's instructions or less (258 M a mute and unmute pair, TASK-88). Reading after a note edit: 3 ms or less (7.1 to 7.4 ms today). Heap of the reading: 20 MB or less (15.1 MB today).
- [ ] #3 Docs follow the change; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a22c402020e677c90: commits 0b3dc8c7 (paw.derived + the chord reading as nodes + kernel fields/stamp/tempo_stamp + K says the chord or 'reading' + status line 'derived' + :checkhealth derived), 9fa88775 (merge main), 255175cb (bench/RESULTS.md). Tests: tests/derived.lua (300 random sets x 6 edits equal to a reading of all notes; a mute with M makes only the muted track's 64 track windows, unmute makes none; a volume change makes nothing; K in the roll says 'reading' then the chord); tests/harmony.lua unchanged and passes; full suite.sh plugins passes; cargo test -p paw-core passes. Numbers against main e18bcfc4, measure lock, cores 16-23, load 28-57: note edit 2.4-5.5 ms (main 5.9-17.9), 15-16 M instructions a pair (main 69-74 M); mute 15.9-19.1 ms (main 29.5-73.6), 71-85 M instructions a mute/unmute pair (main 476-589 M, TASK-88 258 M); heap 19.1 MB (main 15.2). Without the lock at load 44: mute 7.1-8.6 ms, note 2.3-2.5 ms. Deviations from the design: a group node (8 tracks) between track windows and the mix; 'sliced' nodes are makes that call ctx:pause(); spec.touched + span limit what a track change pushes; spec.undo keeps the value before. markers_stamp is left to D8.
<!-- SECTION:NOTES:END -->
