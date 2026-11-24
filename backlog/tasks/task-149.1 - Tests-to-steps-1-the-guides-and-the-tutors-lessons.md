---
id: TASK-149.1
title: >-
  Tests to steps 1: the guides, the tutor's lessons and the tests of the
  extensions
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
ordinal: 221000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-149 (the waits become steps). Read the description of TASK-149 first, and backlog/docs/designs/test-suite-review.md sections 3.1, 3.3, 4 (T4), 5; .claude/skills/lua-testing and prune-tests.

Change each wait of the files below to a step: T.settle, T.advance(ms), T.advance_until(cond, what, ms), T.next_block(n), or an event. Remove each line of these files from tests/timing-allowed.txt. A test that needs real time is marked live (T.live), and checks outcomes only. Prune with the prune-tests skill: name each pruned test and why in the commit.

Files: tests/guides.lua, tests/guides_howto.lua, tests/guides_render.lua, tests/guides_projects.lua, extensions/tutor/tests.lua, and the lessons in extensions/tutor/lua/tutor/lessons (the steps { wait = N } become { advance = N }). Delete the local wait_for helpers of these files. Make the course again (the generator of docs/tutorials/course) if a lesson's text changes.

Size: S to M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tests/timing-allowed.txt has no line for these files
- [x] #2 The files pass three times with suite.sh --shuffle and three seeds (or three runs in a new order, if the shuffle of TASK-151 is not merged)
- [x] #3 The commit names each pruned test and why
- [x] #4 (TASK-149.5) tests/timing-allowed.txt has no line for a test file of an extension, except live tests with a reason
- [x] #5 (TASK-149.5) The files pass three times with three seeds of the shuffle
- [x] #6 (TASK-149.5) The commit names each pruned test and why
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
Branch worktree-agent-ac7697911804a5cd4 on 2f70b19f (batch 17), commits a9399c2f c053f176 e679a3c9 9e1568db. Waits of tests/guides*.lua, the tutor tests and lessons ({ wait = N } -> { advance = N }; recording's sim takes advance), and the tests of vinput, utau, undotree, pattern, sampler, notation (tests_fixes), launcher, drums, continue, articulations, rulerplus, snippets are steps. New T.wakes(fn, device, ...) in tests/suite.lua replaces live meter reads. Make-music guides check an offline render of the bar that played. Live with reason (one :meter( line each): pattern changed-pattern test, utau 'device plays the phrases', utau 'phrase with lyrics is sung'. timing-allowed.txt: no line for the guides, tutor or those extensions except those 3 live lines. Pruned: make music 2's 'synth plays the keys' (guide: connect a MIDI keyboard guards it). Order fixes found by a shuffled order: continue (snippet source), musicops (package.loaded utau), guides_howto step length leak, utau vocal_window zoom (this fixed a failure that was on 2f70b19f too). Verified: 3 seeds each, guides with parts and tests shuffled, extensions with parts shuffled (scratch shuffle; the real --shuffle is not merged). Not done here: plugstate (TASK-148) and doctor (TASK-149.3) lines; sampler tests skip here (no sampler build), not verified. Docs: run-the-tests.md, lua-testing skill, tutor README.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (a9399c2f, c053f176, e679a3c9, 9e1568db). Guides, tutor and extension tests step the clock; T.wakes; three live lines with reasons; pruned test named. Shuffle verified with a scratch shuffle per part. Order problems found: TASK-291.
<!-- SECTION:FINAL_SUMMARY:END -->
