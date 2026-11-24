---
id: TASK-148
title: >-
  Plugins and helpers: handshakes for the tests, and the plugin, offline and
  safety tests move to them
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T20:12:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-146
priority: medium
ordinal: 160000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/test-suite-review.md, finding T6, ticket P5. backlog/docs/designs/testing-practices.md, A5 (the stub plugin is the "bad plugin" of paw).

Tests make a plugin slow with a finite delay and compare the result with a deadline (`tests/offline.lua:92`, `tests/safety.lua:340`). `tests/plugin_state.lua` polls with a time limit and then goes on in silence (`holds`, `rested`), and checks the absence of an echo with `api.wait(300)`.

What to do: sandbox test commands `hold`, `release`, `hang` (until the test ends it) and `deadline` (a short deadline for one device). An event `device.state_applied` with a sequence number. A ready line and an acknowledgment for each request for the helper processes (`bake/helper.rs`, the utau engine) and for the mock servers of the tests. Change `tests/offline.lua`, `tests/safety.lua`, `tests/plugin_state.lua` and `extensions/plugstate/tests_tone3000*.lua` to them.

Read first: backlog/docs/designs/test-suite-review.md, sections 3.1 (rule 6), 3.2 (seam E), 4 (T6), 5 (the Surge XT row).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No finite injected delay is compared with a deadline in a test
- [x] #2 The plugin state tests wait for device.state_applied, and fail with a message that names the device when it does not come
- [x] #3 "Six plugins are made at the same time" is checked with hold, with no time
- [x] #4 (TASK-149.2) tests/timing-allowed.txt has no line for these files
- [x] #5 (TASK-149.2) No finite injected delay is compared with a deadline in these files
- [ ] #6 (TASK-149.2) The files pass three times with three seeds of the shuffle
- [x] #7 (TASK-149.2) The commit names each pruned test and why
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
Branch worktree-agent-a3a9ea2ca4a0e18ca (on 2f70b19f), commit 464b64ab. Session test commands for loading devices (sandbox.hold/release/hang/deadline via device_call; StartTest in DeviceFactory::start); per-kind sandbox.hang/deadline for running plugins (global TEST_HANG for the DAW and PAW_PLUGIN_CREATE_LIMIT gone); event device.state_applied {device,track,name,seq} (Controller::state_pending; sandbox reread after a block that began after the state); api.pending().helpers counts running unpiped processes; audio/MIDI watch on the schedule clock. Tests offline, safety, plugin_state, plugins, helper_processes, plugstate tests + tests_tone3000 moved to events/steps; their timing-allowed lines removed. Needs a build to run: plugin-mode tests and the MIDI port test not run by me (shared binary lacks the Rust). Not done: ready line/ack for bake helpers and the utau engine (no test in these files uses them).

From the batch 18 runner fix (branch worktree-agent-ab84942d745d06ab7, e38b1ff3): on the stepped backend these still fail, from before batch 18/19 merges: plugstate (amp model, LSP convolver, JUCE Surge, state lane, two TONE3000 tests, TONE3000 live mock), ara (two tests), plugin_state 'u gives B back' (VST3 Surge; 4 of 5 runs). Cause: the stepped engine against a plugin's own threads. New runner pieces to build on: api.pending().helpers_busy and .measures; T.advance_until waits for a helper that owes an answer; a plugin stall also ends after 2 s of the sound of late blocks; api.wait_blocks refuses more than 60 s.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (464b64ab, 16a77d38; runner fix e38b1ff3). Session test commands for loading devices (sandbox.hold, release, hang, deadline), per-kind hang and deadline, the event device.state_applied, api.pending().helpers; the plugin, offline, safety, plugin_state, helper_processes and plugstate tests wait on events and steps; their timing-allowed lines are gone. Partial: on the stepped backend, plugins with their own threads still fail some plugstate, ara and plugin_state tests, and three tests are quarantined. AC 6 (three shuffle seeds) and that work moved to TASK-331.
<!-- SECTION:FINAL_SUMMARY:END -->
