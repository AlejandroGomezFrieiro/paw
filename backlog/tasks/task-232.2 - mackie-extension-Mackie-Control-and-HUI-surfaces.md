---
id: TASK-232.2
title: 'mackie extension: Mackie Control and HUI surfaces'
status: To Do
assignee: []
created_date: '2026-11-23T07:12:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - extensions
  - midi
milestone: m-14
dependencies:
  - TASK-228.1
  - TASK-228.2
  - TASK-232.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-232
priority: low
ordinal: 285000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A Mackie Control or HUI surface (Behringer X-Touch, Icon, PreSonus FaderPort in MCU mode) shows eight tracks at a time, moves their faders, pan, mute, solo and arm, shows the names on its display, and has transport keys and a jog wheel.

**What to build.** An extension `mackie`: banks of eight tracks that follow the selection, motor fader feedback (pitch bend per strip), the LCD by SysEx, the time display, transport, jog wheel as the playhead or a nudge. The README names every button.

**Core or extension.** Extension, on top of the SysEx API and the generic learn.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test with the MIDI fakes: an injected fader move (pitch bend on strip 1) moves the fader of the first track in the bank, and one touch is one undo step
- [ ] #2 Lua test: a fader change in paw sends the pitch bend feedback, and a track rename sends the LCD SysEx with the new name
- [ ] #3 Lua test: the bank keys move the bank by eight tracks
- [ ] #4 The README names every button; the README test passes; no real port in the tests
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
