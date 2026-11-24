---
id: TASK-252
title: Microtonal tuning from Scala files
status: To Do
assignee: []
created_date: '2026-11-23T07:16:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-M
  - extensions
  - midi
milestone: m-14
dependencies:
  - TASK-228.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 316000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician plays in just intonation, in a maqam, in 19-TET or in a historical temperament. The notes stay the same MIDI notes (MIDI is the truth), and the tuning sets what pitch they play.

**Other DAWs.** Ardour has microtonal tuning; Bitwig and REAPER read Scala files through plugins or MTS-ESP (design doc, section 4.4 "Microtonal tuning (Scala files)", low).

**paw now (checked 2026-11-23).** paw keeps MIDI 2.0 and per-note pitch bend, and sends MPE (docs/reference/midi.md). No tuning file is read.

**What to build.** An extension `tuning`: read Scala `.scl` and `.kbm` files (and the MIDI Tuning Standard where a synth takes it), set a tuning for a track or the project (data in `meta`), and play it: per-note pitch (MIDI 2.0) or MPE bend for synths that take it, MTS SysEx for synths that take MTS. A project with a tuning opens and plays without the extension, in 12-TET.

**Core or extension.** Extension. If the core must give a generic hook (a per-note pitch offset at play time), that hook is generic and names no tuning (docs/explanation/about-core-and-extensions.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test: a 19-TET .scl file written by the test sets the track tuning, and a C4 to D4 step plays at the 19-TET pitches (per-note pitch sent to the Output fake)
- [ ] #2 Lua test: the project opens and plays without the extension (12-TET)
- [ ] #3 The README names every command and key; the README test passes
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
