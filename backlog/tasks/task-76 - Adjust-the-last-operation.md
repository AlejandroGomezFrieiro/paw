---
id: TASK-76
title: Adjust the last operation
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-22T18:42:00Z'
labels:
  - ux
  - editing
  - epic
milestone: m-4
dependencies: []
priority: high
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Epic. Do not build this ticket: build its children.

Blender's "adjust last operation": after a command with parameters (:quantize 1/16 strength=80, :humanize, :transpose, :velocity, a fade), its parameters can change afterwards and the result updates live, in place of the same undo step (not a new one). Commands declare their adjustable parameters.

Children:
- TASK-76.1: the core, `:adjust` and `<leader>.` (M).
- TASK-76.2: the panel in both frontends (M).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Split on 2026-11-22 into TASK-76.1 and TASK-76.2. Kept as an epic note: set it to Done when both children are merged.

Product owner review 2026-11-22: both children are merged: TASK-76.1 (8d8c2cda) and TASK-76.2 (d9c4e49c).
<!-- SECTION:NOTES:END -->
