---
id: TASK-229
title: 'MIDI-CI discovery: list the MIDI 2.0 devices and what they support'
status: To Do
assignee: []
created_date: '2026-11-23T07:11:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - midi
  - extensions
milestone: m-14
dependencies:
  - TASK-228.1
  - TASK-228.2
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 278000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician with a MIDI 2.0 keyboard or synth sees what it is and what it can do (profiles, properties), and paw sets the device up without manual steps.

**Other DAWs.** Few DAWs have full MIDI-CI yet. The design doc lists it with SysEx (gap 5 of section 4.1, matrix "MIDI ports, MIDI 2.0, MPE: partial").

**paw now.** docs/reference/limits.md: "MIDI-CI has no discovery, profiles or property exchange. MIDI-CI uses SysEx, and the MIDI ports do not send or read SysEx yet."

**What to build.** Discovery first: paw sends a Discovery inquiry to each MIDI 2.0 port and lists the replies (manufacturer, family, model, version, the categories it supports) in `:checkhealth` and in a picker of ports. Profiles and property exchange are later tickets, after an owner review of the first result.

**Core or extension.** An extension (`midici`) over the generic SysEx API. Not all users need it, and the core needs no change beyond SysEx (docs/explanation/about-core-and-extensions.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test with the SysEx fake: a Discovery reply injected as packets shows the device in the list
- [ ] #2 Test: a port with no reply after the inquiry shows as MIDI 1.0 only, with no wait in the test (the test steps the timer)
- [ ] #3 The extension README names every command and key; the README test passes
- [ ] #4 No test opens a real MIDI port
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
