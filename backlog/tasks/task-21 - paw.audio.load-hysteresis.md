---
id: TASK-21
title: paw.audio.load hysteresis
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T18:42:00Z'
labels:
  - ui
milestone: m-6
dependencies: []
priority: low
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cosmetic: the load figure jumps; add hysteresis/smoothing.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Product owner review 2026-11-22: done in code. Commit 494c6c66 averages the load over about 1 s, and runtime/lua/paw/audio.lua M.load changes the shown value only when the average leaves its 2.5% step (hysteresis).
<!-- SECTION:NOTES:END -->
