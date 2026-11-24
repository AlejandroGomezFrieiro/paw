---
id: TASK-197
title: 'plugstate: after u, Surge XT never gets its old octave back (JUCE states test)'
status: Done
assignee: []
created_date: '2026-11-23T02:43:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-2
dependencies: []
priority: high
ordinal: 209000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found at batch 8 (2026-11-23). 'plugstate: JUCE states of Surge XT: byte for byte, the changes by path, a preset of one format in the others' fails at extensions/plugstate/tests.lua:635: after :plugstate.preset_write and u, 'waited 30000 ms in vain for the plugin to hold 1'. It fails on main b48920a4's binary and on batch 8 with TASK-191's Blocks fix, so it is not that race. Find why the undo does not reach the plugin, or why plugstate.slot does not see it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The test passes in suite.sh plugins, 5 runs in a row, with no change of a time
- [ ] #2 The cause is named in the ticket
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause: in paw, not in the test or plugstate. Stopped with nothing that sounds, the engine rests as a whole (engine/rest.rs, after 8 quiet blocks) and runs no device until a message or MIDI event comes. Surge XT VST3 (and the stub CLAP plugin) take a state on only at the start of their next block; load_state sets the device's wake flag, but a resting engine never asks the device. A load with params={} (plugstate preset or its undo) sends no engine message, so the state never reached the plugin. Snapshots (plugin_state.lua) passed because their a_volume parameter sent SetParam, which woke the engine. Timing made it look random: a load within about 1 s of creating the device came before the engine rested. Fix (Rust): paw-engine Msg::Wake (no-op, a message wakes the engine); paw-core sync/devices.rs update_device sends it after each successful load_state. Test: tests/plugin_state.lua 'a state given while the engine rests reaches a plugin that takes it on in its next block' (stub plugin; fails on b404646a binary, 30 s wait). plugstate Lua/Teal unchanged. Branch worktree-agent-af789a4ae527f7b06, commit 58e89a47. Needs a build to verify AC#1.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
