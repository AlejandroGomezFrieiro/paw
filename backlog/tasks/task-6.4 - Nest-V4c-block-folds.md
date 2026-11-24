---
id: TASK-6.4
title: 'Nest V4c: block folds'
status: Done
assignee: []
created_date: '2026-11-22T09:50:00Z'
updated_date: '2026-11-23T08:31:00Z'
labels:
  - nest
  - views
  - folds
milestone: m-2
dependencies:
  - TASK-6.2
parent_task_id: TASK-6
priority: low
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: block folds. A scope with both tracks and time (a visual block) folds into one cell over its rows and its time. This is the last part of V4 of nest.md.

User-visible behavior (nest.md 3.3): a visual block, then `zf`, draws one cell with the block's name over those rows and bars; the other tracks show that time as usual. `za` opens it, `zd` deletes it, `znn` enters it. Playback does not change.

Read first: Design: backlog/docs/designs/nest.md (sections 3.1 to 3.4, 3.10, 5.1, 6 and "Owner decisions, Q13-Q30": every recommended answer is accepted). The reference as V2 left it: docs/reference/narrowing.md (title "Scopes"). The code of V1 and V2: runtime/lua/paw/scope.tl (`current`, `tracks`, `span`, `path`, `breadcrumb`, `local_bar`, `song_bar`, `format`, `enter`, `widen`, `sibling`, `open`, `name`), runtime/lua/paw/layout.tl (`win.scope`, screen.json), tests/scope.lua. Skills: .claude/skills/teal for .tl files, .claude/skills/diataxis-docs and plain-writing for docs. The commits of TASK-6.2, which absorbed TASK-6.3 (the fold state, the beat to column map).

Depends on: TASK-6.2 (it absorbed TASK-6.3).
Do not touch: the engine.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test with real keys: a visual block over two tracks and four bars, then zf, draws one cell; the other tracks still show their clips there
- [x] #2 Test: za opens it, zd removes it, and a render is the same with and without it
- [x] #3 The scene of the arrange view carries the folded cell, so the window can draw it later (paw-gui is paused: no paw-gui change or test); narrowing.md says it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-aa6559b0b506e7d60, commit 56b1e9de (main 7f02e829, up to date). A block fold is a range fold with a list of tracks (paw/folds.tl: is_block, blocks, block_at_cursor; make accepts a range on some tracks). The arrange view draws one cell over the rows of its tracks and its bars, with its name (draw_block_folds), and the other tracks show that time as usual. za toggles, zc closes, zd deletes, znn enters (paw.scope.at_cursor), zw comes back closed; inside the block it is open. The scene of the arrange view carries the cell through the normal buffer ops; paw-gui not changed or tested (paused). Test: tests/folds.lua, real keys <C-v>j16lzf, render null test, scene, za, znn, zw, zd. Docs: narrowing.md (Block folds), keys.md, about-scopes.md, api.md regenerated. Vale 0.

PO 2026-11-23: the two follow-ups that the agent named have tickets: TASK-224 (a closed block is one step of the cursor) and TASK-225 (the block cell shows its bar count).

Merged to main in batch 14 (23350734); full suite and flake-equivalent checks passed.
<!-- SECTION:NOTES:END -->
