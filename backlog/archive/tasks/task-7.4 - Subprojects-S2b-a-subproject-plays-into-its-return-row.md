---
id: TASK-7.4
title: 'Subprojects S2b: a subproject plays into its return row'
status: To Do
assignee: []
created_date: '2026-11-22T09:52:00Z'
updated_date: '2026-11-22T12:38:00Z'
labels:
  - nest
  - subprojects
  - engine
milestone: m-2
dependencies:
  - TASK-7.1
  - TASK-7.2
parent_task_id: TASK-7
priority: medium
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: a subproject's own tracks play in the song, through its return row. This is the chain mode of nest.md 4.4, for the layout of a subproject with its own row (`NestPlay::Master`).

What to build:
- Sync makes one engine track for each pair (nest track, host track) and for the nest's master, places the nest's clips for each instance (follow time: song beat = clip start + nest beat - offset), cuts them at the instance's window, and routes the master into the host track (the return row), as a track into a bus. The N0 spike showed that a track with clips can also be the output of others (crates/paw-engine/tests/bus_clips.rs).
- Two instances on one return row share the engine tracks. A nest on two rows runs its devices twice (`K` will say so in TASK-7.7).
- Tails ring past the end of a block. A muted nest clip mutes its events, not tails that already play.
- The return row's devices, fader, pan and sends act on the subproject's sound.

Read first: Design: backlog/docs/designs/nest.md. The owner accepted every recommended answer (Q1 to Q30: section 7 and "Owner decisions, Q13-Q30"). Words: "subproject" for the user, "nest" in commands and code (Q18). Sections 3.7 ("Its outputs into the song"), 4.4, 8. crates/paw-core/src/sync/mod.rs, sync/clips.rs, sync/routing.rs, sync/mapper.rs, crates/paw-engine/tests/bus_clips.rs; the S1a and S2a commits.

Depends on: TASK-7.1, TASK-7.2.
Do not touch: the transport that plugins see (TASK-7.5), the per-track layout (TASK-7.9).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: a synth in a subproject (made through the API) renders the same as the same synth and notes on a song track at the same place (bit-identical, or below -120 dB with the reason written)
- [ ] #2 Test: two blocks of one subproject on the return row play it twice
- [ ] #3 Test: a muted block is silent, and a reverb tail inside rings past the end of the block
- [ ] #4 Test: the return row's volume and a send to a song reverb act on the subproject's sound
- [ ] #5 Test: an edit inside the subproject reaches the engine and compiles one time (S2a's counter)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Combined into TASK-7.3 (owner, 2026-11-22).
<!-- SECTION:NOTES:END -->
