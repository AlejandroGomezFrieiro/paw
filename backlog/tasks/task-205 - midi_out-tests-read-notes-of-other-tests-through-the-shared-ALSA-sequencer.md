---
id: TASK-205
title: midi_out tests read notes of other tests through the shared ALSA sequencer
status: Done
assignee: []
created_date: '2026-11-23T04:32:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-12
dependencies: []
priority: high
ordinal: 217000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found at batches 8-10 (2026-11-23): paw-engine tests/midi_out.rs:191 'sequencer::a_route_in_mpe_gives_each_note_a_channel_and_its_bend_there' fails about 1 run in 4 of 'cargo nextest -p paw-engine -p paw-core' (passes alone): left [(114, 6), (60, 1), (64, 2), (67, 3)], right [(60, 1), (64, 2), (67, 3)]. A note from another test that runs at the same time reaches its capture. The ALSA sequencer is a resource of the machine, shared by all processes. Make each test hear only its own port (connect only its own client and port, or filter by the source address), or give the sequencer tests a fake behind a trait. Check the other midi_out tests for the same fault.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each midi_out test hears only the notes that it sends; 20 runs of the paw-engine and paw-core tests in parallel pass
- [ ] #2 No midi_out test reads a port that another process can write
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-ab04deaf1af43eb1a, commit fab152d2 (on b48920a4 + merge tree 8163d1a3). midi_out routing moved to Router behind an Output trait (Sink = sequencer, spy in unit tests); sequencer test of tests/midi_out.rs replaced by 2 spy unit tests. MidiInputs::start(sink, select) opens no foreign port before the first select; midi_ports.rs selects only its sender's address; midi_out.lua/midi2.lua call midi_select({}) and name the port by pid. Rust tests to run: cargo nextest -p paw-engine -p paw-core x20 in parallel.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
