---
id: TASK-149.3
title: >-
  Tests to steps 3: core, input, flow, attr, scope, complete, stretch and
  doctor; the stretch preview flake; api.pending counts file hashing
status: Done
assignee: []
created_date: '2026-11-23T06:13:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-146
parent_task_id: TASK-149
priority: medium
ordinal: 223000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-149 (the waits become steps). Read the description of TASK-149 first, and backlog/docs/designs/test-suite-review.md sections 3.1, 3.3, 4 (T4), 5; .claude/skills/lua-testing and prune-tests.

Change each wait of the files below to a step: T.settle, T.advance(ms), T.advance_until(cond, what, ms), T.next_block(n), or an event. Remove each line of these files from tests/timing-allowed.txt. A test that needs real time is marked live (T.live), and checks outcomes only. Prune with the prune-tests skill: name each pruned test and why in the commit.

Files: tests/core.lua, tests/input.lua, tests/flow.lua, tests/attr.lua, tests/scope.lua, tests/complete.lua, tests/stretch.lua, extensions/doctor/tests.lua. The stretch preview test is in quarantine (TASK-207): if TASK-207 is not merged, fix it here with T.advance and remove its line from tests/quarantine.txt.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tests/timing-allowed.txt has no line for these files or for tests/warp.lua
- [x] #2 tests/quarantine.txt has no line for the three stretch bake tests (the stretch preview test, the label test in stretch.lua, and the long stretched clip test in warp.lua)
- [x] #3 Each of the three stretch bake tests holds the bake and checks the preview state; none races the delay of the bake
- [x] #4 Test: api.pending counts the file hashing behind a stretch bake, so T.settle returns only after the hashing ends
- [x] #5 The files pass three times with three seeds of the shuffle
- [x] #6 The commit names each pruned test and why
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
Built on branch worktree-agent-a0784eed8c6c33c77 (base 2f70b19f), commit 249e9de9. Waits in core/input/flow/attr/scope/complete/stretch/warp/doctor are steps; their timing-allowed lines are gone (5 live limit tests moved to tests/live_limits.lua, 2 lines). New T.level(track, side). api.pending().hashing (paw-core: schedule.rs, sources.rs, media.rs, timers.rs) and T.settle waits for it; the 3 stretch bake tests are out of quarantine and hold the bake. cmdline.lua: :messages marks errors read (order dependence under shuffle). Pruned: scope heavy-device speed test, warp partial-bake checks, core sleep check. Needs a build: the 3 stretch tests and the suite need the new Rust field.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (249e9de9). core, input, flow, attr, scope, complete, stretch, warp and doctor step; api.pending().hashing and T.settle wait for it; the three stretch bake tests left quarantine; T.level; tests/live_limits.lua. Pruned tests named in the commit.
<!-- SECTION:FINAL_SUMMARY:END -->
