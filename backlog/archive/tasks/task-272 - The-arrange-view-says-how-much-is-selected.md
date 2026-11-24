---
id: TASK-272
title: The arrange view says how much is selected
status: To Do
assignee: []
created_date: '2026-11-23T08:01:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - ux
milestone: m-15
dependencies: []
priority: medium
ordinal: 336000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen in the screens: a selection shows only as a color, and the status line says only VISUAL, V-LINE or V-BLOCK. Show the size, for example 'bars 3-10 · 3 tracks', in the status line or the message line, the same in each mode. Screens: scratchpad/screens/ui.txt (text) and the owner's page of colored frames; script scratchpad/screens/ui.lua (run with tests/tools/run.sh --clean --no-plugins --audio null --headless -l <script>, SHOTS_OUT, SHOTS_DIR).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A golden screen test with real keys for v, V and <C-v>
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-273 (owner: fewer, larger tickets). Its criteria and text are in TASK-273.
<!-- SECTION:NOTES:END -->
