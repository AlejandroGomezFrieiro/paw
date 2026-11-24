---
id: TASK-227.5
title: 'MIDI Time Code (MTC): send and follow time code'
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
  - TASK-228.1
  - TASK-227.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-227
priority: low
ordinal: 277000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** paw follows or leads a video player, a hardware recorder or another DAW by MIDI Time Code (MTC), with a time offset.

**Other DAWs.** Ardour and REAPER have MTC (design doc, matrix row "MTC, MMC, LTC").

**paw now.** No MTC. Quarter frames are 0xF1 messages (two bytes); a full frame is SysEx.

**What to build.**
- Out: quarter frames at 24, 25, 29.97 drop or 30 fps while paw plays, and a full frame at a locate. An offset (the time code at the song start) is a setting of the project, because it belongs to the film.
- In (follow): paw locates to the time code and plays at the rate of the quarter frames.

**Core or extension.** Core: the engine stamps quarter frames on the audio thread.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test with the Output fake: at 25 fps, quarter frames at the right frames and values; a locate sends a full frame
- [ ] #2 Test: the project offset shifts the time code
- [ ] #3 Test with injected quarter frames: paw locates and plays
- [ ] #4 tests/no_alloc.rs passes; no real MIDI port in the tests
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
