---
id: TASK-249.2
title: 'sampler: play SoundFont 2 (.sf2) files'
status: To Do
assignee: []
created_date: '2026-11-23T07:16:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-M
  - extensions
  - sampler
  - rust
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-249
priority: low
ordinal: 313000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**What to build.** In extensions/sampler: read a SoundFont 2 file (presets, instruments, zones, generators for key and velocity ranges, loop points, the volume envelope, tuning) and play it as an SFZ instrument plays. The preset is part of the device state. A picker lists the presets of the file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a small SF2 file built by the test (one sample, two zones) plays the right sample for each key and loops at its loop points
- [ ] #2 Lua test: the picker lists the presets of the test file, and a choice is one undo step
- [ ] #3 No test reads a SoundFont of the machine
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
