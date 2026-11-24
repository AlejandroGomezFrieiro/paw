---
id: TASK-166
title: paw-engine midi_out tests assert on wall-clock lateness
status: Done
assignee: []
created_date: '2026-11-22T22:12:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels: []
milestone: m-12
dependencies: []
priority: high
ordinal: 178000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
crates/paw-engine/tests/midi_out.rs messages_leave_when_they_are_stamped_for asserts each note came less than 2 ms early and 40 ms late (wall clock), and an_engine_sends_what_a_track_plays_and_ends_it_when_stopped failed the same run. Both failed in batch 3's nextest -j 6 (2026-11-23) and passed alone: a timing check, which AGENTS.md forbids. Fix: test the stamps that the engine gives (the frame or time it asks the MIDI port for) through a fake port behind a trait, not the arrival time; move the lateness numbers to bench/. Until then the two tests are in tests/quarantine.txt.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No assert in midi_out.rs compares a wall-clock time with a number
- [ ] #2 The tests guard that a message is sent for its stamp and that stop ends held notes
- [ ] #3 Their lines leave tests/quarantine.txt
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a9f10ec955136f0ed on main c386d3a4: 2531db21 (reapply of the reverted merge) + f3a69462 (the engine test expects the reset that SetClips sends in the track's first block, then the two notes; stamps a beat apart within 1 us; stop sends the reset). messages_leave_when_they_are_stamped_for stays deleted (queue_time unit test + benches/midi_lateness.rs). quarantine.txt: three TASK-166 lines removed. timing-allowed.txt: midi_out.rs Instant::now 4, thread::sleep 1 (stall guards of the MPE sequencer test). testlint passes.
<!-- SECTION:NOTES:END -->
