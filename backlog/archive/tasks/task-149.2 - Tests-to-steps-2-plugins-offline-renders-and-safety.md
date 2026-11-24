---
id: TASK-149.2
title: 'Tests to steps 2: plugins, offline renders and safety'
status: To Do
assignee: []
created_date: '2026-11-23T06:13:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-146
  - TASK-148
parent_task_id: TASK-149
priority: medium
ordinal: 222000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-149 (the waits become steps). Read the description of TASK-149 first, and backlog/docs/designs/test-suite-review.md sections 3.1, 3.3, 4 (T4), 5; .claude/skills/lua-testing and prune-tests.

Change each wait of the files below to a step: T.settle, T.advance(ms), T.advance_until(cond, what, ms), T.next_block(n), or an event. Remove each line of these files from tests/timing-allowed.txt. A test that needs real time is marked live (T.live), and checks outcomes only. Prune with the prune-tests skill: name each pruned test and why in the commit.

Files: tests/offline.lua, tests/safety.lua, tests/plugin_state.lua, tests/plugins.lua, tests/helper_processes.lua, extensions/plugstate/tests.lua, extensions/plugstate/tests_tone3000.lua. They need the handshakes of TASK-148 (hold, release, hang, deadline, device.state_applied).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tests/timing-allowed.txt has no line for these files
- [ ] #2 No finite injected delay is compared with a deadline in these files
- [ ] #3 The files pass three times with three seeds of the shuffle
- [ ] #4 The commit names each pruned test and why
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-148 (owner: fewer, larger tickets). Its criteria and text are in TASK-148.
<!-- SECTION:NOTES:END -->
