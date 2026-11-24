---
id: TASK-5
title: Nested regions (R1, R2)
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T09:08:00Z'
labels:
  - nest
  - regions
milestone: m-2
dependencies: []
priority: high
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regions nest by time containment (core): ir/ar innermost, 2ar parent, ]r [r same level, moving a parent moves children, :region.remove!, picker tree, render regions by level with path names; ruler region lane as a tree through paw.ruler. Design: backlog/docs/designs/nest.md section 3.8.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
R1 and R2 done on branch worktree-agent-aad9a8d2c76ccab29: e708ac67 (R1: tree by containment in paw.markers, 2ar/2ir, ]r [r, region.move/move!, region.remove!, moves take children, tree picker, render.regions path names and level=, range= paths), 9a604069 (R2: paw.ruler lanes, the regions lane a row per level with regionlevels and RulerRegion1/2/Deep, pointer by row, paw.scope.children for region scopes, :narrow prefers regions inside the scope), merge of main 7d17bce1. zm/zr region folds left for V4 (no time folds yet). Full suite plugins: 1 failure (stretch label timing) that passes alone; paw-gui tests pass.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged: nested regions by containment, 2ar, ]r [r, parent moves children, remove!, render by path/level, ruler region lane tree, scope children. zm/zr waits for V4 (time folds).
<!-- SECTION:FINAL_SUMMARY:END -->
