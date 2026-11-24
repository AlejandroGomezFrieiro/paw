---
id: TASK-227.2
title: 'Follow MIDI clock from a MIDI port: start, stop, song position and tempo'
status: To Do
assignee: []
created_date: '2026-11-23T07:11:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - midi
  - sync
milestone: m-14
dependencies:
  - TASK-227.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-227
priority: low
ordinal: 274000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A hardware sequencer or another program is the master. paw starts, stops, locates and keeps tempo when the master does.

**Other DAWs.** Qtractor follows MIDI clock and SPP; REAPER and Ardour follow MIDI clock (design doc, matrix row "MIDI clock").

**paw now.** No clock in. MIDI in is crates/paw-core/src/session/midi_in.rs; `paw.midi.inject_ump` injects a packet as if from a port (docs/reference/midi.md).

**What to build.**
- A setting of the machine: follow the clock of one port. Off by default.
- Start, Continue, Stop and Song Position move the transport. The clock rate sets the tempo of playback, smoothed over a few beats, without a write to the project tempo map (the project stays the truth; a command can write the measured tempo as one undo step).
- A clear message when the clock stops or jitters too much.

**Core or extension.** Core: the transport and the engine clock.

**Note.** This is harder than clock out (a varispeed of the engine). Do it after the clock out subtask.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with injected packets: Start starts the transport, Stop stops it, Song Position locates to the right beat
- [ ] #2 Test with injected clock at 100 BPM: playback reaches 100 BPM; the project tempo map does not change
- [ ] #3 A command writes the measured tempo into the project as one undo step
- [ ] #4 No test uses a real port or wall-clock time: the tests inject packets with time stamps and step the engine
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Each acceptance criterion is met, and the notes give its evidence
- [ ] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [ ] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [ ] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [ ] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [ ] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [ ] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [ ] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->
