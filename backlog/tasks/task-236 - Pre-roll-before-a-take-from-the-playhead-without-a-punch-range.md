---
id: TASK-236
title: Pre-roll before a take from the playhead, without a punch range
status: To Do
assignee: []
created_date: '2026-11-23T07:13:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-S
  - recording
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 294000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician records a take from the playhead and hears one or two bars before it, without setting a punch range. A pre-roll is also needed in parts of a bar for a take that starts on an upbeat.

**Other DAWs.** REAPER has pre-roll before a recording; Ardour has pre-roll (design doc, matrix row "Pre-roll": P).

**paw now (checked 2026-11-23).** `paw.opt.pre_roll` (bars) and `paw.opt.pre_roll_seconds` exist (docs/reference/recording.md, crates/paw-core/src/session/transport.rs `pre_roll_start`). Pre-roll applies only when punch is on and the transport is stopped. docs/reference/limits.md says "Pre-roll without a punch ... Pre-roll in parts of a bar". The seconds option already gives parts of a bar, so that part of limits.md is stale. Also, the ranges disagree: options.md says 0 to 64 bars and 0 to 60 s; recording.md and the code say 0 to 16 bars and 0 to 30 s.

**What to build.** With pre-roll on and punch off, a record from a stop plays from the pre-roll before the playhead and starts the take at the playhead (the takes keep only the part from the playhead). Fix the ranges in options.md and the stale line in limits.md.

**Core or extension.** Core: recording and the transport.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys on the null backend: with pre_roll = 1 and punch off, record at bar 5 plays from bar 4 and the take starts at bar 5
- [ ] #2 Test: with pre_roll_seconds = 0.5, the song plays from half a second before the playhead
- [ ] #3 options.md, recording.md and limits.md agree with the code on the ranges and the behavior; Vale reports 0 alerts
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
