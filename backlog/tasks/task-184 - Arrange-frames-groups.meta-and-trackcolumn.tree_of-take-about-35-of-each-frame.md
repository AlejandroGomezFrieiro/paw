---
id: TASK-184
title: >-
  Arrange frames: groups.meta and trackcolumn.tree_of take about 35 % of each
  frame
status: Done
assignee: []
created_date: '2026-11-23T00:26:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels: []
milestone: m-3
dependencies: []
priority: medium
ordinal: 196000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-6.7's profile (2026-11-23, bench/profile/run.sh scope): in the arrange view, in the song as well as in scopes, groups.meta and trackcolumn.tree_of take about 35 % of every frame. Keep their results between frames, keyed like the screen keeps windows (the project's edit count and the events sent), or compute them once per frame. Also: bench/profile/drive.py's keys scenario sends Esc and :q in one write, which paw reads as q (a macro); send them apart.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A frame of the arrange view on the scope scenario costs less, with numbers in bench/RESULTS.md (spread, measured under external load)
- [ ] #2 A test counts the builds of the group tree per frame (work, not time)
- [ ] #3 The keys scenario closes the roll with Esc and :q as two writes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a64414700dab9162b (TASK-6.7 merged in first, then main bc16df6d). Commits fee00488, 98eb696b, 763069d3. trackcolumn.tl keeps the group tree by tracks drawn + window + folds.generation + project edits (the old key held a new folds.list() table each call, so most lines rebuilt it); paw.trackcolumn.tree_builds counts builds. groups.tl keeps marks and group of each track by project edits + events sent (scope.tl's key); writers read fresh. paw-core put_project counts as an edit (so the cache sees another project in the same turn): needs a build; test 'groups: a project opened in the turn...' fails on the old binary. drive.py keys: Esc and :q as two writes. Frame of song/region 11 -> 5.5 ms; scope-changing keys (znn, ]z, znag) higher in the one-shot scenario but equal in repeat runs, cause not found (bench/RESULTS.md).
<!-- SECTION:NOTES:END -->
