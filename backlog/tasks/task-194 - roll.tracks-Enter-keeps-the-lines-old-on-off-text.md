---
id: TASK-194
title: ':roll.tracks: Enter keeps the line''s old on/off text'
status: Done
assignee: []
created_date: '2026-11-23T02:07:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-2
dependencies: []
priority: low
ordinal: 206000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-126 (2026-11-23): :roll.tracks's Enter action read a third argument (the picker) to change the text of the line, but pick.tl never passes it and makes the entry text only once, so after Enter the line keeps its old on/off text. TASK-126 removed the dead code; behavior unchanged. Fix: let a picker source refresh an entry's text after its action (generic, in pick.tl), and use it here.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After Enter on a track in :roll.tracks, its line shows the new state, by a test with real keys
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed on branch worktree-agent-a2e7d0595cc7fed33, commit 9ae6a94c (on b48920a4 + merge of f5adec5e, TASK-126). Generic: contracts.PickAction<T>.refresh; pick.tl describe() makes the entry's line again after such an action (same entry table in entries and matches: order, selection kept). :roll.tracks Enter uses refresh = true. Test with real keys in tests/roll_tracks.lua (fails without the fix). Docs: reference/pickers.md, explanation/about-teal.md.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
