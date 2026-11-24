---
id: TASK-274
title: Controller moves in a clip and linked faders show in the arrange view
status: To Do
assignee: []
created_date: '2026-11-23T08:01:00Z'
updated_date: '2026-11-23T08:20:00Z'
labels:
  - ux
milestone: m-15
dependencies: []
priority: medium
ordinal: 338000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen in the screens: controller moves (CC, bend) inside a MIDI clip do not show in the arrange view, so a linked copy that shares them looks like a plain copy apart from ≡. A group with linked faders (:group.link) has no mark on its row. Screens: scratchpad/screens/ui.txt (text) and the owner's page of colored frames; script scratchpad/screens/ui.lua (run with tests/tools/run.sh --clean --no-plugins --audio null --headless -l <script>, SHOTS_OUT, SHOTS_DIR).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A clip with controller moves shows them (a mark or a small curve) in the arrange view (golden screen)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-273 (owner: fewer, larger tickets). Its criteria and text are in TASK-273.
<!-- SECTION:NOTES:END -->
