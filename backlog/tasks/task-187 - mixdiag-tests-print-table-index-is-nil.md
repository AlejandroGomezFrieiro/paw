---
id: TASK-187
title: mixdiag tests print 'table index is nil'
status: Done
assignee: []
created_date: '2026-11-23T00:32:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels: []
milestone: m-12
dependencies: []
priority: medium
ordinal: 199000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen by TASK-134 (2026-11-23): the mixdiag tests print 'table index is nil' while they run. Find which code sets a table key from nil, and whether a test hides a real error (a pcall that swallows it).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The message is gone and its cause is fixed
- [ ] #2 If it was a real error, a test fails without the fix
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause: mixdiag emits render.before with path = nil (a measurement writes no file). The handler in runtime/lua/paw/address.tl did pending_opts[e.path] = e.opts, so paw.try showed 'table index is nil' as an error message at each measurement (also to the user). Fix: the handler skips a payload without a path (as paw/qf.tl does). paw.failure now keeps the place (file:line) of a 'table index is' error. Test: 'mixdiag: <leader>ma measures the mix without an error message' fails on main with got "table index is nil". Docs: events.md render.before row. Branch worktree-agent-ab04d28ebe2dce550, commit e6c143fb.
<!-- SECTION:NOTES:END -->
