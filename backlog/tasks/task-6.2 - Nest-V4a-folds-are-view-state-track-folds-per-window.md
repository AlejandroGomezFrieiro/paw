---
id: TASK-6.2
title: >-
  Nest V4: folds are view state (track folds per window, time folds, region
  folds by level)
status: Done
assignee: []
created_date: '2026-11-22T09:50:00Z'
updated_date: '2026-11-22T18:49:00Z'
labels:
  - nest
  - views
  - folds
milestone: m-2
dependencies:
  - TASK-6.1
parent_task_id: TASK-6
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Combined ticket (owner, 2026-11-22): one agent builds TASK-6.2, TASK-6.3 in order, with one build, one suite run and one merge. Commit after each part.

Goal: folds are view state, as in Vim: each window keeps its own folds, a fold is never an undo step, and the project keeps them in screen.json. Track folds of any set of tracks. This is the first part of V4 of nest.md.

User-visible behavior (nest.md 3.3, 3.4; owner decision Q14):
- Group folds move from the group's `meta` (`group_folded`: project data, an undo step) to each window. Two windows can fold differently. No compatibility: the old `group_folded` key is ignored on read and no longer written (owner: no compatibility before a release).
- `za` toggles the fold at the cursor, `zc` closes it (`zo` stays zoom out), `zR` opens all, `zM` closes all, in this window.
- `zf{motion}` makes a fold of the tracks that the motion covers: `zfag` the group, `Vjjzf` three tracks. The fold is a named scope: the group's name, else `Fold 1`. It draws its rows as one row with its name.
- `zd` deletes the fold at the cursor (the fold, never a track or clip). `zE` deletes every fold of the window.
- `znn` on a fold enters it; `zw` from inside comes back to it, closed as it was.
- The window frontend draws the same folds (the scene).

Read first: Design: backlog/docs/designs/nest.md (sections 3.1 to 3.4, 3.10, 5.1, 6 and "Owner decisions, Q13-Q30": every recommended answer is accepted). The reference as V2 left it: docs/reference/narrowing.md (title "Scopes"). The code of V1 and V2: runtime/lua/paw/scope.tl (`current`, `tracks`, `span`, `path`, `breadcrumb`, `local_bar`, `song_bar`, `format`, `enter`, `widen`, `sibling`, `open`, `name`), runtime/lua/paw/layout.tl (`win.scope`, screen.json), tests/scope.lua. Skills: .claude/skills/teal for .tl files, .claude/skills/diataxis-docs and plain-writing for docs.
Also: runtime/lua/paw/groups.tl (`folded` near line 140, `fold` near line 332, `group_folded`, `rows`); runtime/lua/paw/trackcolumn.tl; runtime/lua/paw/defaults/keys.lua (`za`, `zM`, `zR` near lines 218 to 230); runtime/lua/paw/defaults/tracks.lua (`track.fold`); docs/explanation/about-groups-and-vcas.md, docs/how-to/organize-tracks.md, docs/how-to/work-on-one-group.md.

Depends on: TASK-6.1 (both change trackcolumn.tl and the arrange rows).
Do not touch: time folds (TASK-6.3).

Size: M.

## Part of TASK-6.3: Nest V4b: time folds, and region folds by level (zm, zr)

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
- [ ] #1 (6.2) Test with real keys: :vs, then za on a group in one window: the other window shows the group open; the undo tree does not change
- [ ] #2 (6.2) Test: fold a group, :w, open the project again: the fold is back in that window (screen.json); the group's meta has no group_folded
- [ ] #3 (6.2) Test: Vjjzf folds three tracks into one row named Fold 1; zd removes the fold and the three tracks are still there; zE removes every fold
- [ ] #4 (6.2) Test: znn on a fold enters it; zw comes back with the fold closed
- [ ] #5 (6.2) The window frontend draws the folds (tests/scene_parity.lua or paw-gui tests); cargo test --release -p paw-gui passes
- [ ] #6 (6.2) narrowing.md (or a folds section), keys.md, about-groups-and-vcas.md and the group how-tos are true again; Vale 0 errors
- [ ] #7 (6.3) Test with real keys: zfar on an 8-bar region draws one column 'Bridge ▸ 8'; l from the bar before it moves past it in one step
- [ ] #8 (6.3) Test: a render with the fold and without it is bit-identical
- [ ] #9 (6.3) Test: with Chorus 2 holding Verse A and Verse B, zm closes Verse A and Verse B, a second zm closes Chorus 2, zr opens Chorus 2 again
- [ ] #10 (6.3) Test: znn on the folded column enters the region; zw comes back with it closed
- [ ] #11 (6.3) Test (arrange_mouse): a click two bars after a fold puts the cursor on the right beat
- [ ] #12 (6.3) The ruler and the window frontend draw the folded column (tests/arrange_scene.lua, paw-gui tests)
- [ ] #13 (6.3) A frame with 10 time folds costs no more than 1 ms over a frame without folds (bench/profile keys on project.lua)
- [ ] #14 (6.3) narrowing.md (folds), keys.md and the ruler reference say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built TASK-6.2 and TASK-6.3 together on branch worktree-agent-a7af6141ded22b48d (commits 2dfd367e, 62c722bc, 8034c94b, main merged up to the latest). New module paw/folds.tl: folds are view state per window (win.folds, win.foldlevel, screen.json, no undo step; group_folded is gone). Keys za zc zd zE zM zR zf zm zr, commands :fold.*. Track folds (Vjjzf -> Fold 1 row, zfag), time folds (zfar -> 'Bridge ▸ 8' column, range folds, region levels), one beat->column map in the arrange view, its mouse and the ruler; clips cut in pieces; playhead jumps in the terminal and paw-gui; render unchanged. Tests: tests/folds.lua, tuimouse, arrange_scene, paw-scene unit test. Full suite with plugins passes. 10 time folds cost about 0.5 ms a frame (instructions), under the 1 ms of AC 13.

Merged main again (6cbc0e56): TASK-7.3, 117, 15, 76.2, 61, 18. znn takes a closed time fold first, then a subproject clip. TASK-15's lane sampler reads the fold map. Folds use the tracks of the scope, because track_list is now the song's tracks only. Generated files made again with apidoc. Full suite with plugins: 2 timing failures under load average 46 to 60 (help made at idle; notation page speed). Both passed when run again.
<!-- SECTION:NOTES:END -->
