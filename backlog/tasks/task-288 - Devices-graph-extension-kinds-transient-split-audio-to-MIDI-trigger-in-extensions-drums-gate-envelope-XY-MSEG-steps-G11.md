---
id: TASK-288
title: >-
  Devices graph: extension kinds (transient split, audio-to-MIDI trigger in
  extensions/drums, gate, envelope, XY, MSEG, steps) (G11)
status: To Do
assignee: []
created_date: '2026-11-23T11:58:00Z'
updated_date: '2026-11-24T14:22:00Z'
labels:
  - agent:builder
milestone: m-18
dependencies:
  - TASK-280
  - TASK-285
documentation:
  - backlog/docs/designs/devices-graph.md
priority: low
ordinal: 350000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The core must stay generic: an extension adds split kinds and modulators as Lua devices with N outputs. The metal drum chain needs a transient split and a snare trigger that makes notes in its branch. Design section 4.2 and 9.7.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An extension adds a split kind with a schema, and the view, the keys and the chain language take it with no core change
- [ ] #2 extensions/drums has an audio-to-MIDI trigger device that plays a sampler in the same branch
- [ ] #3 transient, gate, envelope and xy split kinds, and mseg and steps modulators, each with a test
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
