---
id: TASK-227.4
title: 'MMC: MIDI Machine Control starts, stops, records and locates paw'
status: To Do
assignee: []
created_date: '2026-11-23T07:11:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-S
  - midi
  - sync
milestone: m-14
dependencies:
  - TASK-228.1
  - TASK-228.2
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-227
priority: low
ordinal: 276000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A control surface or a hardware recorder starts, stops, records and locates paw with MIDI Machine Control (MMC). paw can also send MMC to a hardware recorder.

**Other DAWs.** Qtractor has MMC in and out (design doc, matrix row "MTC, MMC, LTC").

**paw now.** No MMC. MMC is SysEx (F0 7F <device> 06 <command> F7), and the ports do not send or read SysEx yet.

**What to build.**
- In: MMC Play, Stop, Record Strobe, Record Exit, Locate and Pause from a chosen port move the transport. The device id is a setting.
- Out: paw sends MMC Play, Stop and Locate to a chosen port when its transport moves.

**Core or extension.** Core for the setting and the transport moves, on top of the generic SysEx API. It is small and uses no device names.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test: injected MMC Play, Stop and Locate move the transport; Record Strobe starts a take on the armed tracks
- [ ] #2 Test with the Output fake: paw sends MMC Play and Stop when its transport starts and stops
- [ ] #3 A message from another device id does nothing
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
