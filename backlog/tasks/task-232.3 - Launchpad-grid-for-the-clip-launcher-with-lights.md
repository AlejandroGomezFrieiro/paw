---
id: TASK-232.3
title: Launchpad grid for the clip launcher, with lights
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
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-232
priority: low
ordinal: 286000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A Launchpad (or a similar grid) launches the slots and scenes of the clip launcher, and its pads light in the colors of the clips and blink while they wait to start.

**paw now.** The clip launcher (extensions/launcher) has learn targets for one pad at a time (`:learn launch`). No grid maps all pads at once, and no light feedback is sent.

**What to build.** In the launcher extension, or a small extension `grid`: a map of an 8x8 grid to the session view, the lights by note-on velocity (and the programmer mode by SysEx), and arrows that move the grid.

**Core or extension.** Extension.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test with the MIDI fakes: an injected note from pad (1,1) launches slot 1 of the first track in the grid
- [ ] #2 Lua test: a launched clip lights its pad (note-on with the color velocity sent to the Output fake), a queued clip blinks
- [ ] #3 The README names every pad and key; the README test passes; no real port in the tests
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
