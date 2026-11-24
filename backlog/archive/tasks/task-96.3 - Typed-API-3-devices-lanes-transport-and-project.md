---
id: TASK-96.3
title: 'Typed API 3: devices, lanes, transport and project'
status: To Do
assignee: []
created_date: '2026-11-23T06:14:00Z'
updated_date: '2026-11-23T08:21:00Z'
labels:
  - architecture
  - api
milestone: m-10
dependencies:
  - TASK-96.1
parent_task_id: TASK-96
priority: medium
ordinal: 234000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-96 (one typed source for the shapes of paw.api). Read its description first, and backlog/docs/designs/architecture-review.md (F2, Owner decisions). .claude/skills/rust-skills and teal. Keep the error texts that Lua or a user sees, and nil for absent fields in Lua.

The same change as TASK-96.1 for the views and patches of devices, lanes, the transport and the project. Split it in two when an agent starts it, if it is more than a day.

Size: M to L.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No json! and no serde_json::Value in these paths of paw.api
- [ ] #2 Their Teal records are generated; apidoc check and tools/tlcheck.sh pass
- [ ] #3 An unknown key in each kind of patch gives a clear error that names the key; a test covers each
- [ ] #4 The full Lua suite passes with no change of behavior
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: merged into TASK-96.2 (owner: fewer, larger tickets). Its criteria and text are in TASK-96.2.
<!-- SECTION:NOTES:END -->
