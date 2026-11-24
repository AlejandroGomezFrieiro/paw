---
id: TASK-216
title: 'Runtime: the command registry below the project layer'
status: To Do
assignee: []
created_date: '2026-11-23T06:42:00Z'
updated_date: '2026-11-23T08:21:00Z'
labels:
  - architecture
  - runtime
  - layers
milestone: m-10
dependencies:
  - TASK-215
priority: low
ordinal: 244000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-209: paw.command (17) and paw.commands (16) are read upward by lower layers (33 exceptions). Move the command registry down so that modules below the project layer can define commands without an upward read. After the timers ticket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The command registry (paw.command, paw.commands) is in a module below the project layer, and the commands keep their names and behavior
- [ ] #2 The 33 upward references to paw.command and paw.commands are gone from tools/layers-allowed.txt, and luajit tools/layers.lua passes
- [ ] #3 The full Lua suite passes; extensions.md and api.md are true; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: criteria added; depends on TASK-215 (same layer files). Size: M.

PO 2026-11-23: merged into TASK-215 (owner: fewer, larger tickets). Its criteria and text are in TASK-215.
<!-- SECTION:NOTES:END -->
