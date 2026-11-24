---
id: TASK-165
title: >-
  Engine: a note's start frame depends on the block size (rounding of the play
  position)
status: Done
assignee: []
created_date: '2026-11-22T21:52:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels: []
milestone: m-6
dependencies: []
priority: high
ordinal: 177000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-153's null tests (2026-11-22, branch worktree-agent-ae91ce7eac5ec48fb). Beats per frame is not exact in f64; the play position adds up rounding error block by block, and play_clips (crates/paw-engine/src/engine/work.rs) rounds the frame down. A simulation of the engine's arithmetic found 400 notes one frame off between blocks of 64, 128 and 512 over 38 s at 120 BPM, and some at 140 and 93 BPM. The null test uses 87.890625 BPM (a frame is exactly 2^-15 beat) to avoid it. Fix: event frames that do not depend on the block size, for example an integer frame clock with the tempo map applied per event.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A render at 120 BPM with blocks of 64 and of 512 gives the same samples (the null test of TASK-153 gets a 120 BPM row)
- [ ] #2 A tempo ramp renders the same at block sizes 64, 128 and 512
- [ ] #3 The audio thread still allocates nothing (no_alloc tests pass)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a02984d5b2d668784 on main c386d3a4: c52ada81 reapplies the reverted merge, 01adf14e fixes the batch failures (effects at rest hold through silent frames: Rest::holds; sleeps no longer wakes; audio regions placed by the clock: Clock::first_frame_at/frames_into; media.lua 32-bit hash 83a9c860, proved right by simulation; 24-bit hash still needs the new value from a run). Ignore on one_project_rendered_two_ways_nulls removed. Tests to run: paw-core sync::tests::one_project_rendered_two_ways_nulls; paw-engine devices::testkit::an_effect_sounds_the_same_whether_it_sleeps_or_not, engine::clock::tests, clips::a_reversed_region_plays_its_stretch_of_the_source_from_the_end, the paw-engine and paw-core suites; Lua suite.sh only media.
<!-- SECTION:NOTES:END -->
