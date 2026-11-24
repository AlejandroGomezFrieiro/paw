---
id: TASK-240.1
title: 'Design: wide buses, surround panning and more side-chain inputs'
status: To Do
assignee: []
created_date: '2026-11-23T07:14:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-S
  - design
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-240
priority: low
ordinal: 302000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**What to build.** A design document in backlog/docs/designs/ for wide buses, as the parent ticket lists. Read crates/paw-engine (the mix), crates/paw-plugins (bus layouts of CLAP, VST3, LV2), docs/reference/routing.md and render.md first. Compare with Ardour and REAPER. Give a plan of parts, each a day or less, and the questions for the owner with a recommendation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The design document is in backlog/docs/designs/ with a plan of parts and the owner questions
- [ ] #2 It says what stays stereo, what the terminal shows and how a render writes more than two channels
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): The design must use the channels property of a lane type and the port types of ADR 0028, and strips and buses as nodes of the part graph (ADR 0027). It can start, but its implementation tickets wait for TY.
<!-- SECTION:NOTES:END -->
