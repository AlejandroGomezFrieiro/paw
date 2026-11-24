---
id: TASK-350
title: >-
  Rust sweep leftovers: one TruePeak, paw-mcp Meter on TempoMap, the last byte
  readers
status: To Do
assignee: []
created_date: '2026-11-24T10:51:00Z'
labels:
  - agent:worker
  - quality
dependencies: []
priority: medium
ordinal: 419000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the review of TASK-342 (2026-11-24). (1) R2: export one allocation-free TruePeak from paw-measure; the engine Upsampler (meter, limiter) and the analysis interpolator use it; the meter and limiter tests compare with analyze. (2) R2: paw-mcp music.rs:18 Meter becomes a thin wrapper of TempoMap. (3) Byte readers: paw-core/src/session/tags.rs:154 and paw-raster/src/kitty.rs keep their own readers; use one shared reader (paw-types or a small crate), short input gives None. (4) find_bundles with walkdir skips a broken symlink named *.vst3 that the old walk listed: list it, so the scan says it is broken. (5) clap/host.rs extern C callbacks expect() a poisoned lock and abort: recover the lock (into_inner) or return the plugin's error value.
<!-- SECTION:DESCRIPTION:END -->

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
