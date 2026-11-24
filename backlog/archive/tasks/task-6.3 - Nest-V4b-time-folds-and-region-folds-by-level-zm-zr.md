---
id: TASK-6.3
title: 'Nest V4b: time folds, and region folds by level (zm, zr)'
status: To Do
assignee: []
created_date: '2026-11-22T09:50:00Z'
updated_date: '2026-11-22T12:38:00Z'
labels:
  - nest
  - views
  - folds
milestone: m-2
dependencies:
  - TASK-6.2
parent_task_id: TASK-6
priority: medium
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: time folds. A region or a range of bars folds into one narrow column of the arrange view, so that the view shows only what you work on. The song plays through it unchanged. Region folds go by level, as Vim's foldlevel. This is the main part of V4 of nest.md, and the owner's TIMEFOLD idea.

User-visible behavior (nest.md 3.3, 3.4, 3.8 "Time folds by level"; owner decision Q29):
- `zfar` folds the region at the cursor: one column with its name and length, `Bridge ▸ 8`. A visual selection of bars on every track, then `zf`, folds a range (`Fold 1`).
- The columns after it move left. Motions (`l`, `w`, `b`, `e`) take a folded span as one step, as `j` `k` take a folded group. The cursor on it shows its name in the status line.
- Playback does not change. The playhead jumps over the column. A render is the same.
- A clip that crosses a folded span is drawn cut at its edges.
- `za`, `zc`, `zd`, `zE`, `zR`, `zM` work on time folds too. `zm` closes one more level of region folds, `zr` opens one, as Vim's foldlevel (`regionfoldlevel`; `zm` closes the deepest open level first). `zn` or `<CR>` on a time fold enters it.
- The ruler draws the folded column, through the `regions` part of `paw.ruler` (R2: `folded`, the glyphs `▾` `▸`).
- The mouse: a click after a fold goes to the right beat.
- The window frontend draws the same scene.

How: one map from beats to columns with the folded spans (`view:col(beat)` and `view:beat(col)`). Every place in the arrange view, the ruler and the mouse code that changes beats into columns uses it.

Read first: Design: backlog/docs/designs/nest.md (sections 3.1 to 3.4, 3.10, 5.1, 6 and "Owner decisions, Q13-Q30": every recommended answer is accepted). The reference as V2 left it: docs/reference/narrowing.md (title "Scopes"). The code of V1 and V2: runtime/lua/paw/scope.tl (`current`, `tracks`, `span`, `path`, `breadcrumb`, `local_bar`, `song_bar`, `format`, `enter`, `widen`, `sibling`, `open`, `name`), runtime/lua/paw/layout.tl (`win.scope`, screen.json), tests/scope.lua. Skills: .claude/skills/teal for .tl files, .claude/skills/diataxis-docs and plain-writing for docs. nest.md 3.8 (the region tree), backlog/docs/designs/queue-2026-11-21.md ("TIMEFOLD").
Also: runtime/lua/paw/markers.tl (`tree`, `children`, `parent`, `path`); runtime/lua/paw/ruler.tl (lanes, the `regions` part); runtime/lua/paw/views/arrange.lua (`col`, the scroll, drawing), runtime/lua/paw/views/arrange_mouse.lua; runtime/lua/paw/scene.tl; the arrange drawing in crates/paw-gui; the V4a commit (fold state per window).

Depends on: TASK-6.2.
Do not touch: block folds (TASK-6.4), the engine (playback does not change).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: zfar on an 8-bar region draws one column 'Bridge ▸ 8'; l from the bar before it moves past it in one step
- [ ] #2 Test: a render with the fold and without it is bit-identical
- [ ] #3 Test: with Chorus 2 holding Verse A and Verse B, zm closes Verse A and Verse B, a second zm closes Chorus 2, zr opens Chorus 2 again
- [ ] #4 Test: znn on the folded column enters the region; zw comes back with it closed
- [ ] #5 Test (arrange_mouse): a click two bars after a fold puts the cursor on the right beat
- [ ] #6 The ruler and the window frontend draw the folded column (tests/arrange_scene.lua, paw-gui tests)
- [ ] #7 A frame with 10 time folds costs no more than 1 ms over a frame without folds (bench/profile keys on project.lua)
- [ ] #8 narrowing.md (folds), keys.md and the ruler reference say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Combined into TASK-6.2 (owner, 2026-11-22).
<!-- SECTION:NOTES:END -->
