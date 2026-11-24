---
id: TASK-85
title: Linked clips with local overrides
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-23T06:11:00Z'
labels:
  - nondestructive
  - midi
  - epic
milestone: m-2
dependencies: []
priority: medium
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Epic. Do not build this ticket: build its children.

Blender's linked data and library overrides: duplicate a MIDI clip as linked (edit one, all change), with overrides for each copy (transpose, velocity; a modifier stack later with TASK-75), and :clip.unlink to make a copy. Shares the idea of nest links (TASK-7, S10) and the shared compiled events (TASK-7, S2a).

Children:
- TASK-85.1: duplicate as linked, unlink (M).
- TASK-85.2: overrides for each copy (M).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Split on 2026-11-22 into TASK-85.1 and TASK-85.2. Kept as an epic note: set it to Done when both children are merged.

Board review 2026-11-23: both children are Done and on main (Merge TASK-85.1 93743ba2, Merge TASK-85.2 c1edd2cd). The follow-up for the bend marks and A.move_note on a transposed copy is TASK-176.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Linked clips: duplicate as linked and unlink (TASK-85.1), overrides for each copy (TASK-85.2). Both are merged. TASK-176 is the follow-up.
<!-- SECTION:FINAL_SUMMARY:END -->
