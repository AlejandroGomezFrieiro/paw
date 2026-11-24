---
id: TASK-331
title: >-
  Tests: the stepped engine waits for the threads of a plugin; plugstate, ara
  and plugin_state pass on steps
status: In Progress
assignee: []
created_date: '2026-11-23T20:11:00Z'
updated_date: '2026-11-24T16:08:00Z'
labels:
  - tests
  - plugins
  - agent:builder
milestone: m-12
dependencies:
  - TASK-292
  - TASK-294
priority: high
ordinal: 400000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-148 and the batch 18 runner fix (e38b1ff3). On the stepped backend, tests of plugins that run their own threads still fail: plugstate (amp model, LSP convolver, JUCE Surge, state lane, two TONE3000 tests, the TONE3000 live mock), ara (two tests), plugin_state 'u gives B back' (VST3 Surge, 4 of 5 runs). Cause: the stepped engine does not wait for the work that a plugin does on its own threads. tests/quarantine.txt has three lines with the fix text 'the stepped engine waits for the threads of a plugin' (two ara tests, the vinput tracker), and AGENTS.md wants a ticket for each line.

Build on the runner pieces of batch 18: api.pending().helpers_busy and .measures, T.advance_until waits for a helper that owes an answer, a plugin stall ends after 2 s of late blocks, api.wait_blocks refuses more than 60 s. Start after EL1 (TASK-292): it gives the honest stepped backend and the one turn. Read the notes of TASK-148 and TASK-292 first. No sleep, no deadline as an assertion.

Also from TASK-148: the files of TASK-148 pass three times with three seeds of the shuffle (its AC 6), and a ready line or acknowledgment for bake helpers and the utau engine where a test needs one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The plugstate, ara and plugin_state tests that the notes of TASK-148 name pass on the stepped backend, 20 of 20 with suite.sh repeat 20
- [ ] #2 tests/quarantine.txt has no line with the fix text 'the stepped engine waits for the threads of a plugin'
- [ ] #3 The files of TASK-148 (offline, safety, plugin_state, plugins, helper_processes, plugstate) pass three times with three seeds of the shuffle
- [ ] #4 The cause and the fix are in the notes, and the lua-testing skill says how a test waits for the work of a plugin's threads
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
PO 2026-11-24: EL1 (TASK-292) is on main. Dependency on EL2 (TASK-294) added: EL2 changes the wait of the loop (doorbell, quiet), and the wait for a plugin's threads builds on it. Start after batch 22 merges.

Wave 23 (2026-11-24), base 9cecbfdc (batches 20-22 + W1).

Sweep add-on (2026-11-24): CORE-4 (no sleep loops on the kernel thread: session.rs settle_plugins, statelanes.rs:353, devices.rs:481, loading.rs:313,325, io.rs:477; MIDI input queue). Resumes after TASK-342 lands, because TASK-342 edits paw-engine and paw-plugins.

Builder report 2026-11-24 (branch stepped-plugins): six causes. 1 device_load slept, so no block ran on the stepped engine. 2 quiet did not count a plugin's own threads. 3 Surge reports values from its own thread after the state is set. 4 a parameter reaches the plugin only in its next block. 5 the ARA test plug-in sleeps while it analyzes (new attachment method paw.busy). 6 vinput is not a plugin case. Fix: the session reads plugin state back after the plugin's next blocks (proposed ADR 0040), and the stepped engine waits for plugin threads and paw.busy. AC1: Surge snapshot 5/5 (repeat 5, not 20); ara 20/20. AC3: one shuffle seed (11) only.
<!-- SECTION:NOTES:END -->
