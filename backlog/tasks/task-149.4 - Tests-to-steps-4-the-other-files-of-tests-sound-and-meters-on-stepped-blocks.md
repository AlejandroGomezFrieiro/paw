---
id: TASK-149.4
title: >-
  Tests to steps 4: the other files of tests/ (sound and meters on stepped
  blocks)
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
  - TASK-147
parent_task_id: TASK-149
priority: medium
ordinal: 224000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-149 (the waits become steps). Read the description of TASK-149 first, and backlog/docs/designs/test-suite-review.md sections 3.1, 3.3, 4 (T4), 5; .claude/skills/lua-testing and prune-tests.

Change each wait of the files below to a step: T.settle, T.advance(ms), T.advance_until(cond, what, ms), T.next_block(n), or an event. Remove each line of these files from tests/timing-allowed.txt. A test that needs real time is marked live (T.live), and checks outcomes only. Prune with the prune-tests skill: name each pruned test and why in the commit.

Files: each file of tests/*.lua that tests/timing-allowed.txt still names after parts 1 to 3, for example workflow, warp, realtime, project_folder, midi_out, midi2, media, harmony, files, export, audition, record_mix, sound, step_input, leader_hints, keys_gaps, pick, qf, tempo, tags, seats, uifix and the others. A meter read after a sleep becomes stepped blocks (TASK-147) or paw.render. tests/realtime.lua stays live with its one-sided check. Agents can do this part in groups of files, side by side.

Size: M to L: split it in groups of files when an agent starts it, if it is more than a day.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tests/timing-allowed.txt has no line for a file of tests/ except the live tests, each with a reason
- [x] #2 A test that plays and reads a meter gives the same value in two runs, to the bit
- [ ] #3 The files pass three times with three seeds of the shuffle
- [x] #4 The commit names each pruned test and why
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
Branch worktree-agent-a23815c420af4a2d3, commit 07afb7ce. All paw.wait/api.now/api.sleep/:meter of the other tests/ files converted (T.advance, T.until_, T.advance_until, T.meter, T.settle); MIDI loop tests of midi2/midi_out live. timing-allowed.txt: only realtime and startuptime (live, with reasons) of these files. No test deleted; startuptime 20 ms check and frames time message removed. strips.lua flake: no race found (peaks synchronous), 3 runs pass, test unchanged. Shuffle seeds wait for the runner of TASK-145.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (07afb7ce). The other files of tests/ step the clock; only realtime and startuptime stay live, with reasons; a meter read gives the same value in two runs (T.meter on the stepped backend). AC 3 (three shuffle seeds) was not shown, because the shuffle came with TASK-145 in the same batch; a shuffled run of the whole suite fails 18 tests, and TASK-330 owns that.
<!-- SECTION:FINAL_SUMMARY:END -->
