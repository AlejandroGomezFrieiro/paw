---
id: TASK-227.3
title: 'JACK transport: paw starts, stops and locates with other JACK programs'
status: To Do
assignee: []
created_date: '2026-11-23T07:11:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - sync
  - engine
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-227
priority: medium
ordinal: 275000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** paw plays together with other JACK or PipeWire programs (Hydrogen, Ardour, Carla, sequencers). Play, stop and a jump in one program move all of them. One program can be the timebase master and give the bar and the tempo.

**Other DAWs.** Qtractor has JACK transport; Non Timeline drives it from its tempo map; Ardour has it (design doc, matrix row "JACK", section 2).

**paw now (checked 2026-11-23).** The research doc said "not verified". It is a real gap: `jack` is only a cpal host (crates/paw-engine/src/backend/cpal.rs). cpal gives no access to the JACK transport, and no code in the repository calls a transport function.

**What to build.**
- A transport link behind a trait in the engine, so that the tests use a fake. The real link uses the `jack` crate (or the PipeWire JACK library) next to the cpal audio. It works also when the audio backend is PipeWire, because pipewire-jack gives the JACK transport.
- Follow: paw starts, stops and locates when the JACK transport does.
- Lead: paw moves the JACK transport when the user plays, stops or jumps.
- Timebase master (optional, a setting): paw gives bar, beat and tempo from its tempo map.

**Core or extension.** Core: the transport and the engine clock. The setting is of the machine.

**Tests.** No JACK server in a test. A fake transport link gives and takes states.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test with a fake transport link: a start of the fake starts the paw transport, a locate moves the playhead to the same frame
- [ ] #2 Rust test: play, stop and a jump in paw move the fake transport
- [ ] #3 Rust test: as timebase master, paw gives the bar, beat and tempo of its tempo map at a frame
- [ ] #4 No test needs a JACK server or PipeWire; the real link is only built and not run in the tests
- [ ] #5 docs/reference/audio-devices.md says how to turn it on
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
