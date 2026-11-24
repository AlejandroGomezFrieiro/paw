---
id: TASK-249
title: 'sampler: SFZ modulation and SoundFont 2 files'
status: To Do
assignee: []
created_date: '2026-11-23T07:16:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-L
  - extensions
  - sampler
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 311000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician loads SFZ libraries that use LFOs and the v2 envelopes (vibrato, filter sweeps, swells), and SoundFont 2 (`.sf2`) files, which many free libraries still use.

**Other DAWs.** Zrythm has SFZ and SF2; LMMS has SF2; Ardour hosts sfizz (design doc, section 4.2 "Sampler: no LFO, v2 envelopes, effects; whole-file load", low).

**paw now (checked 2026-11-23).** extensions/sampler (Rust, CLAP). docs/reference/limits.md: it does not play `amplfo_*`, `fillfo_*`, `pitchlfo_*`, `lfoN_*`, `egN_*`, `<effect>`, `amp_keytrack`, `sw_vel`, nor read SoundFont 2, folders of samples or `.dslibrary`.

**What to build.** The subtasks. Effects (`<effect>`) stay out: paw devices do that job on the track.

**Core or extension.** Extension (sampler).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each subtask is done
- [ ] #2 The sampler README and limits.md say what it plays now; Vale reports 0 alerts
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
