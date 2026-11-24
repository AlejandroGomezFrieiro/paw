---
id: TASK-228.1
title: Send SysEx to a MIDI port from Lua
status: To Do
assignee: []
created_date: '2026-11-23T07:11:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - midi
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-228
priority: medium
ordinal: 270000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** An extension or a user script sends a SysEx message to a MIDI port: a patch dump to a synth, an LCD text to a control surface, an MMC command.

**paw now.** `Wire` in crates/paw-engine/src/midi_form.rs holds three bytes at most. The output thread of crates/paw-engine/src/midi_out.rs hands each message to the ALSA sequencer. The `Output` trait in that file has a fake for the tests (`Sent`).

**What to build.**
- `paw.midi.send_sysex(port, bytes)` in Lua (and the `paw.api` function under it). The message leaves through the output thread, not the audio thread, because a SysEx has a variable length.
- On a port that takes UMP, the message leaves as SysEx7 data packets (message type 3). On a MIDI 1.0 port, it leaves as F0 ... F7 bytes.
- A clear error for a bad message (no F0 start, a data byte above 0x7F, an unknown port).

**Core or extension.** Core: ports are core.

**Rules.** The audio thread does not allocate, lock or wait (AGENTS.md). If the engine sends SysEx from a clip later (subtask "Clips keep SysEx events"), it uses a buffer made before.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test with the Output fake: a SysEx of 300 bytes leaves whole, as F0...F7 on a MIDI 1.0 port and as SysEx7 packets on a UMP port
- [ ] #2 Lua test: paw.midi.send_sysex with a bad message gives a clear error, not a stack trace
- [ ] #3 No test opens a real MIDI port or an ALSA sequencer: the tests use the Output fake
- [ ] #4 tests/no_alloc.rs passes
- [ ] #5 docs/reference/midi.md and the API doc comments say it
- [ ] #6 A test seam for Lua: a fake MIDI output port that a Lua test reads back (over the Output trait), so that the tests of extensions check what leaves without the ALSA sequencer; tests/midi_out.lua moves to it where it can
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
