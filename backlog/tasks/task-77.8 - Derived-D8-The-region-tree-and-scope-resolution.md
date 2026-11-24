---
id: TASK-77.8
title: 'Derived D8: The region tree and scope resolution'
status: Done
assignee: []
created_date: '2026-11-22T15:23:00Z'
updated_date: '2026-11-23T08:31:00Z'
labels:
  - performance
  - derived
milestone: m-3
dependencies:
  - TASK-77.1
parent_task_id: TASK-77
priority: medium
ordinal: 127000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
D8 of the derived-data design. `markers.tl` `tree()` becomes a memo with `markers_stamp` as its key; `scope.tl` `tracks()` a memo with the scope, the groups and `markers_stamp` as its key.

Read first: backlog/docs/designs/derived.md, part 4 (the design) and row D8 of part 5; part 2 (inventory) and part 3 (measurements) for the consumer.

Owner decisions (2026-11-22): the design is approved; Q1 no mark in the views (the status line shows the job only after 1 s, K on a chord says "reading"); Q2 paw.derived stays internal in D1 to D5 and becomes public in D6; Q3 no user option for memory, fixed limits per kind shown by :checkhealth derived.

Measure with the spread, on the bench project, against main at the time, measured under external load.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test: A note edit does not build the tree again (`stats().made` stays). `tests/markers.lua` and the scope tests pass.
- [x] #2 Number to meet: `tree()` with 500 regions after a note edit: 0.05 ms or less.
- [x] #3 Docs follow the change; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a49ca17ab54b73b79: 5e1211f4 (code+tests), ec5da2aa (bench/RESULTS.md), a4812afc (merge of main 7f02e829). markers.tl tree() is a memo (markers.tree) that reads a new generic source 'project' (derived.tl marks it on project.changed: name, meta, tempo) with the regions' text as inputs (early cutoff, undo gives the old tree back). No Rust markers_stamp: project.changed already never fires on a note edit; the text compare runs only after a change of the project's own fields. scope.tl tracks() is a memo (scope.tracks) per scope of the song keyed by the text of its levels: track list, plus each track's meta for a scope with a group; regions give no source (they never limit tracks); scopes in a subproject are not kept (no event on a reorder of a nest's tracks). scope.tl region() reads markers.node. Numbers (25 note edits, 500 regions, 5 pairs, load 13-18): tree() 1.07-1.41 ms -> 0.0015-0.0027 ms (made 0 times); tracks(group) 0.75-0.84 -> 0.0020-0.0031 ms. Tests: tests/regions.lua and tests/scope.lua, one each.

PO 2026-11-23: the agent names one limit: the scopes of a subproject are not kept in the memo (no event on a reorder of a nest's tracks). It is a speed limit only, so no follow-up ticket now. Make one if a bench shows scopes in a subproject as slow.

Merged to main in batch 14 (23350734); full suite and flake-equivalent checks passed.
<!-- SECTION:NOTES:END -->
