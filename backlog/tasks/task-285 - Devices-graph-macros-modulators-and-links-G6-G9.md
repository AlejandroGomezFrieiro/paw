---
id: TASK-285
title: 'Devices graph: macros, modulators and links (G6, G9)'
status: To Do
assignee: []
created_date: '2026-11-23T11:58:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-16
dependencies:
  - TASK-280
  - TASK-282
  - TASK-301
documentation:
  - backlog/docs/designs/devices-graph.md
priority: medium
ordinal: 347000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each container (the root too) has a modulation lane: macros, LFOs, envelope followers, MIDI sources, random. A link goes from a source to a parameter of the same container. CLAP plugins get the modulation as CLAP_EVENT_PARAM_MOD, which does not change the saved value. Design sections 4.6 and 6.6; the link mode of v1 is gone (gm is an operator).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 gM makes a parameter a macro of its container; a macro has a lane and shows on the macro face and the mixer strip
- [ ] #2 lfo, follower, midi and random sources run in the plan with no allocation
- [ ] #3 gm links a source to the parameters of a motion or a selection; ] [ change the depth; :mod.bake writes a link to automation
- [ ] #4 Undo of a link and of a macro is one step each
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
PO 2026-11-23 (plan V2 bundles): Bundle G6. The modulator kinds are ModulatorFamily of A1 (TASK-301); no own registry.

From G3 (2026-11-24): the inspector shows macro rows with sliders, but no modulators and no gm/gM: take them here. The variant chip of the header waits for a variant model.
<!-- SECTION:NOTES:END -->
