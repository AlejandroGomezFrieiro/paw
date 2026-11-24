---
id: TASK-228
title: MIDI ports send and receive SysEx (System Exclusive)
status: To Do
assignee: []
created_date: '2026-11-23T07:11:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-L
  - midi
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: medium
ordinal: 269000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician loads and saves the sounds of a hardware synth (patch dumps), sets its parameters, talks to a control surface, and uses MMC. All of these use System Exclusive (SysEx) messages.

**Other DAWs.** Ardour, Qtractor, MusE and REAPER send and receive SysEx through their MIDI ports (design doc, gap 5 of section 4.1; matrix "MIDI ports, MIDI 2.0, MPE: partial").

**paw now (checked 2026-11-23).**
- MIDI out: crates/paw-engine/src/midi_out.rs. `Wire` (crates/paw-engine/src/midi_form.rs) is a UMP of two words or a MIDI 1.0 message of three bytes at most. No SysEx leaves.
- MIDI in: crates/paw-core/src/session/midi_in.rs gives `midi.in` events of channel voice messages. A SysEx from a port is lost.
- Clips: crates/paw-core/src/clipfile.rs keeps notes and controls only. MIDI file import (runtime/lua/paw/midifile.tl) counts SysEx as "skipped".
- docs/reference/limits.md says that the ports do not send or read SysEx, and that MIDI-CI waits for it.

**What to build.** The subtasks: send, receive, and keep SysEx in clips and MIDI files.

**Core or extension.** Core. Ports and the audio thread are core (docs/explanation/about-core-and-extensions.md). Extensions (control surfaces, patch librarians, MIDI-CI) build on a generic SysEx API, so the core change is generic and names no device.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each subtask is done
- [ ] #2 docs/reference/midi.md tells how to send and receive SysEx; limits.md no longer says that ports do not send or read SysEx; Vale reports 0 alerts
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
