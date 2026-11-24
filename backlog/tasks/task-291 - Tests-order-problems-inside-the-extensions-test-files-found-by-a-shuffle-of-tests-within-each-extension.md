---
id: TASK-291
title: >-
  Tests: order problems inside the extensions' test files (found by a shuffle of
  tests within each extension)
status: Done
assignee: []
created_date: '2026-11-23T13:13:00Z'
updated_date: '2026-11-23T23:03:00Z'
labels: []
milestone: m-12
dependencies: []
priority: medium
ordinal: 353000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A shuffle of the tests inside each extension's test files showed order problems that do not involve time: vinput's panel and port listing, tutor 'skipping a step', notation popover, templates, utau 'right edge stretches'. Log of seed 22: scratchpad t149_1/within_part_shuffle_22.txt (agent of TASK-149.1). Also: notation layout 'systems break balanced' fails with module 'notation.breaks' not found when it runs after the stretch tests. And the undotree A/B test compares the playhead with a 0.25-beat limit while the engine runs on the wall clock.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each listed test passes in 3 shuffle seeds with tests shuffled inside each part
- [x] #2 notation layout passes after the stretch tests
- [x] #3 The undotree A/B test steps the clock instead of reading the playhead twice
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Commit 81d061d2 (same branch). Each cause was state an earlier test left: vinput panel row/scroll and run lists reset in load(); templates folder emptied in load(); notation popover prompt histories emptied in song(); notation breaks and skyline tests call load() before require (the 'module notation.breaks not found' error); utau gui_as_new() resets tool, panels, zoom, scroll, top; audition 50 ms limit uses an epsilon for a float error; tutor V j y step needs a new yank (ctx.before); undotree A/B checks the playhead exactly on the stepped engine. continue and musicops pass shuffled unchanged. Verified by the agent with seeds 11, 22, 33 on a borrowed binary; re-run with the batch 19 binary before Done.

PO 2026-11-23: TASK-330 (18 order problems of a shuffled run of the whole suite) builds on this branch; merge this first.

On main in batch 20 (5041115e, pushed 2026-11-24 with the tag pre-parts). Full suite passed after one test fix (5041115e: three tests and the time-axis test expected the null backend); nix flake check passed.

PO 2026-11-24: ACs checked from the agent's evidence (seeds 11, 22, 33) and the full suite of batch 20. TASK-330 runs the shuffle of the whole suite and catches a regression.
<!-- SECTION:NOTES:END -->
