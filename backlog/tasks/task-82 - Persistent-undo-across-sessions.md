---
id: TASK-82
title: Persistent undo across sessions
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-22T18:42:00Z'
labels:
  - ux
  - editing
  - undo
  - epic
milestone: m-4
dependencies: []
priority: medium
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Epic. Do not build this ticket: build its children.

Neovim's undofile: reopen a project and still undo past the last save. The undo tree is stored beside the project's state (not in the project folder), bounded in size.

Children:
- TASK-82.1: read a project folder from files in memory (S).
- TASK-82.2: the undo file (M).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Split on 2026-11-22 into TASK-82.1 and TASK-82.2. Kept as an epic note: set it to Done when both children are merged.

Product owner review 2026-11-22: TASK-82.1 absorbed TASK-82.2 and is merged (cf15cd12: ProjectFiles from memory, the undo file).
<!-- SECTION:NOTES:END -->
