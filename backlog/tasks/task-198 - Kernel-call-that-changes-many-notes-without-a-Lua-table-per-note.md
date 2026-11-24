---
id: TASK-198
title: Kernel call that changes many notes without a Lua table per note
status: Done
assignee: []
created_date: '2026-11-23T02:43:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-3
dependencies: []
priority: medium
ordinal: 210000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-192 (2026-11-23): in :%quantize on Verse B, ex.items costs 17 ms (4 ms is the kernel giving each note as a table) and ex.apply 12 ms (7 ms is the kernel taking 6,400 changes). Design one paw.api call for a bulk edit of notes (for example ids and new starts as arrays, or a transform the kernel applies), keeping one undo step. Numbers in bench/RESULTS.md with their spread, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A bulk note edit goes through one call with no Lua table per note
- [ ] #2 One undo step, and the existing quantize tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design: paw.api.notes_set(columns), columns = { clip = {ids}, place = {places from 1, before the call}, start/length/pitch/velocity = {values} } (each list as long as clip; a list left out keeps that field). The kernel reads the lists directly (mlua Vec, no table or serde per note), checks every entry first (clip, place, values via check_notes, a note given twice, list lengths) and makes one edit_named over all clips (one undo step; the events come from the flush diff, so they are the same as N clip_notes_edit calls). Guard: defined with define!, so guarded! like every paw.api function; api_boundary walks it. meta/attr/remove stay on clip_notes_edit. Used in paw.ex.apply (columns for notes of clips with no removal, meta or attr) and :quantize (builds the columns directly). Not done: the read side (ex.items, 4 ms of note tables) - a follow-up could give notes as columns too. Branch worktree-agent-a8f86a56dd62ce021, commit 8a3d8a5e (on b48920a4 + b404646a + TASK-192 branch). Numbers after the orchestrator's build.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
