---
id: TASK-219
title: 'Extensions: no paw.<name> entries in package.loaded'
status: To Do
assignee: []
created_date: '2026-11-23T06:42:00Z'
updated_date: '2026-11-23T08:21:00Z'
labels:
  - extensions
milestone: m-10
dependencies: []
priority: low
ordinal: 247000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-209: ara, articulations, mixdiag, sampler, utau and plugstate set package.loaded['paw.<name>'] (for example utau/init.lua:17); the plugstate README documents require('paw.plugstate'). A future core module of the same name would break them. Give extensions their own namespace and update the READMEs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No bundled extension sets a package.loaded entry under paw. (git grep)
- [ ] #2 Each of ara, articulations, mixdiag, sampler, utau and plugstate is required by its own name; their callers, tests and READMEs use the new name
- [ ] #3 The Lua suite passes; Vale reports 0 alerts on the changed READMEs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23: criteria added. Size: S. No backward compatibility before a release, so no alias for the old names.

PO 2026-11-23: merged into TASK-218 (owner: fewer, larger tickets). Its criteria and text are in TASK-218.
<!-- SECTION:NOTES:END -->
