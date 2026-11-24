---
id: TASK-144
title: >-
  Tests: kernel state in the leak check, the utau helper paints first, no
  literal ids
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels:
  - tests
  - better-testing
milestone: m-3
dependencies:
  - TASK-121
priority: high
ordinal: 156000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/test-suite-review.md, finding T7, ticket P6.

The fingerprint of TASK-121 sees registries (options, hooks, timers, keys, extensions). It does not see the state of a module of an extension or of the kernel. Known cases:
- `vocal_window()` (`extensions/utau/tests_singing.lua:365`) clicks before the window was painted. The pointer handler uses the geometry of the last paint (`utau/gui.lua:175`). Under `only`, the two vocal editor tests fail 5 of 5 times.
- Kernel state that `T.fresh()` does not reset: the MIDI test ports (`api.midi_test_ports`), the engine backend (`api.engine_restart`), the window history of `<C-w>p`, the step input bindings, the id counter of the kernel.
- `extensions/projdiff/tests.lua` writes literal kernel ids (lines 110, 120, 135, 312 to 319).

What to do: add the MIDI test ports, the engine backend, the timers due and the window history to the fingerprint. Make `vocal_window()` paint before it clicks. Take the ids in `projdiff` from the kernel. Write rule 7 ("a test makes all the state that it reads") in docs/how-to/run-the-tests.md.

Read first: backlog/docs/designs/test-suite-review.md, sections 3.1 (rule 7), 4 (T7), 5 and 7. TASK-121.

Overlaps: TASK-121 (this ticket can be its last part).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 suite.sh only "the vocal editor" passes
- [ ] #2 The leak check names a test that leaves a MIDI test port
- [ ] #3 No literal kernel id in a test of projdiff; the ids come from the kernel
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a220c59e972e7efc8, commit 3e4a0a1f and merge of main 0495e357. See the agent report for the details.
<!-- SECTION:NOTES:END -->
