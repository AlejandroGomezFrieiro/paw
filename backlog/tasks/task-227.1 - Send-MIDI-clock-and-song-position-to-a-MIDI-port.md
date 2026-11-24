---
id: TASK-227.1
title: Send MIDI clock and song position to a MIDI port
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
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-227
priority: medium
ordinal: 273000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A drum machine, an arpeggiator or a hardware sequencer plays in time with paw. It starts when paw starts, follows the tempo map, and continues from the right bar after a jump.

**Other DAWs.** Qtractor (MIDI clock, SPP), REAPER, Ardour (design doc, matrix row "MIDI clock").

**paw now.** No clock out. The engine clock is crates/paw-engine/src/engine/clock.rs; MIDI output is crates/paw-engine/src/midi_out.rs (stamped messages on a lock-free queue, the `Output` trait).

**What to build.**
- A setting of the machine: the ports that get the clock (`paw.opt.clock_out = { "port name" }`, or a `:sync` command). Off by default.
- 24 clock messages (0xF8) per beat, stamped by the tempo map, ramps too. Start (0xFA) at play from bar 1, Song Position (0xF2) then Continue (0xFB) at play from another place, Stop (0xFC) at stop. The loop wrap sends a Song Position and continues.
- The output latency and the delay compensation shift the clock as they shift the notes, so the gear sounds together with the tracks.
- The status line shows a mark while the clock is out.

**Core or extension.** Core: the engine stamps the messages on the audio thread (no allocation, no lock).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test with the Output fake: at 120 BPM, 24 clocks per beat at the right frames; a tempo change changes the spacing at its frame
- [ ] #2 Rust test: play from bar 5 sends Song Position then Continue; play from bar 1 sends Start; stop sends Stop; a loop wrap sends Song Position
- [ ] #3 tests/no_alloc.rs passes with the clock on
- [ ] #4 No test opens a real MIDI port: the tests use the Output fake
- [ ] #5 Lua test: the setting turns the clock on and off and the status line shows the mark
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
