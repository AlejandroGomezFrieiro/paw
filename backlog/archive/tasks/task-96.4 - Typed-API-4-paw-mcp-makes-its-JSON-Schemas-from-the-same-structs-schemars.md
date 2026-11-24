---
id: TASK-96.4
title: 'Typed API 4: paw-mcp makes its JSON Schemas from the same structs (schemars)'
status: To Do
assignee: []
created_date: '2026-11-23T06:14:00Z'
updated_date: '2026-11-23T08:21:00Z'
labels:
  - architecture
  - api
  - mcp
milestone: m-10
dependencies:
  - TASK-96.1
parent_task_id: TASK-96
priority: medium
ordinal: 235000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-96 (one typed source for the shapes of paw.api). Read its description first, and backlog/docs/designs/architecture-review.md (F2, Owner decisions). .claude/skills/rust-skills and teal. Keep the error texts that Lua or a user sees, and nil for absent fields in Lua.

paw-mcp writes its JSON Schemas by hand (crates/paw-mcp/src/tools/write.rs, schema.rs). Make them with schemars from the structs of TASK-96.1 to TASK-96.3 (owner question 3 of the review: accepted). Do the areas that are typed; add each later area when it is typed.

Size: S to M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The schemas of the typed areas come from schemars; the hand schemas of those areas are gone
- [ ] #2 The paw-mcp protocol tests pass; a test checks that a schema lists the fields of its struct
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-96 (owner: fewer, larger tickets). Its criteria and text are in TASK-96.
<!-- SECTION:NOTES:END -->
