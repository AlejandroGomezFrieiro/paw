---
id: TASK-227
title: >-
  Play in time with other gear and programs: MIDI clock, MMC, MTC and JACK
  transport
status: To Do
assignee: []
created_date: '2026-11-23T07:10:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-L
  - midi
  - sync
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: medium
ordinal: 268000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician plays paw together with a drum machine, a hardware sequencer, a modular rig or another program (Hydrogen, Ardour, Carla). The other gear must start, stop and keep tempo with paw, or paw must follow it.

**Other DAWs.** Qtractor has MIDI clock, song position (SPP), MMC and JACK transport. Ardour has a Synchronization chapter (LTC, MTC, MIDI clock, JACK). REAPER has MIDI clock and MTC. Design doc: gap 1 of section 4.1, matrix "Sync and control".

**paw now (checked 2026-11-23).** No sync of any kind.
- JACK is only an audio host of cpal (crates/paw-engine/src/backend/cpal.rs, `jack` host). No code reads or sets the JACK transport.
- MIDI output (crates/paw-engine/src/midi_out.rs) sends channel voice messages only. `Wire::Midi1` holds at most three bytes, so no SysEx leaves (MMC and MTC full frames are SysEx).
- No code sends or reads 0xF8 clock, 0xFA/0xFB/0xFC start, continue and stop, 0xF2 song position or 0xF1 quarter frames.

**What to build.** The subtasks of this ticket, one for each protocol. The engine clock (crates/paw-engine/src/engine/clock.rs) is the master. Each protocol is a setting of the machine, not of the project, because the ports and the gear belong to the studio.

**Core or extension.** Core. The clock and the transport are in the engine, and MIDI ports are core (docs/explanation/about-core-and-extensions.md: "MIDI 1.0 and 2.0 input ... ports, and the audio thread"). An extension cannot send a message at a sample-accurate time.

**Out of scope.** LTC (an audio time code for film work: low demand for paw users). Ableton Link has its own ticket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each subtask is done
- [ ] #2 docs/reference/midi.md (or a new page docs/reference/sync.md) and a how-to guide tell how to sync paw to a drum machine; Vale reports 0 alerts
- [ ] #3 docs/reference/limits.md lists what sync does not do
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
