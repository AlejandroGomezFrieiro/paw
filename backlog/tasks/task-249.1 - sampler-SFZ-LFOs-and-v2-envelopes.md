---
id: TASK-249.1
title: 'sampler: SFZ LFOs and v2 envelopes'
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
ordinal: 312000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**What to build.** In extensions/sampler: the SFZ v1 LFOs (`amplfo_*`, `fillfo_*`, `pitchlfo_*`), the v2 LFOs (`lfoN_*`) and the v2 envelopes (`egN_*`) with their targets (amplitude, pitch, cutoff, pan), and `amp_keytrack`. The audio thread rules hold (no allocation, no lock).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a generated SFZ with pitchlfo_freq=5 and pitchlfo_depth=100 renders a note whose pitch moves 100 cents at 5 Hz (measured on the output)
- [ ] #2 Rust test: an eg1 on the cutoff opens the filter over its attack time
- [ ] #3 The no-allocation test of the sampler passes with modulation
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
