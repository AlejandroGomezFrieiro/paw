---
id: TASK-6.1
title: 'Nest V3: views in a scope'
status: Done
assignee: []
created_date: '2026-11-22T09:43:00Z'
updated_date: '2026-11-22T12:51:00Z'
labels:
  - nest
  - views
milestone: m-2
dependencies:
  - TASK-4
parent_task_id: TASK-6
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: every view and every command sees the scope of its window, also its time. This is V3 of nest.md.

User-visible behavior (nest.md 3.2):
- Piano roll: in a scope, only the clips of the scope's tracks that overlap its time; `0`, `$`, `gg`, `G` stop at the scope's edges, as in the arrange view.
- Arrange: a clip that crosses an edge of the scope is drawn cut, with `‹` or `›` at the cut. An edit of it is an edit of the whole clip.
- Track column: `number` counts the scope's tracks from 1; a sign `›` on the first row says that the window is in a scope.
- Ex: `%` is the scope's tracks and time, also for note commands (`:%quantize` changes only the notes inside the scope's time). Bar numbers are local (owner decision Q13). `@19` names a song bar: `:tempo 96 at @19`, `:@19`, `@19|`.
- Text objects: `ie` is the entire scope; `ar` the region inside the scope (cut at its edges); `it` the track in the scope's time. So `dar` in `Song › Bridge › Strings` deletes only the strings' clips in the region.
- The mixer, the device panel, the session view, `paw://tracks` and the pickers follow the scope already (V1, V2): check them, do not write them again.
- The window frontend shows the same: the cuts and the sign are in the scene.

Read first: Design: backlog/docs/designs/nest.md (sections 3.1 to 3.4, 3.10, 5.1, 6 and "Owner decisions, Q13-Q30": every recommended answer is accepted). The reference as V2 left it: docs/reference/narrowing.md (title "Scopes"). The code of V1 and V2: runtime/lua/paw/scope.tl (`current`, `tracks`, `span`, `path`, `breadcrumb`, `local_bar`, `song_bar`, `format`, `enter`, `widen`, `sibling`, `open`, `name`), runtime/lua/paw/layout.tl (`win.scope`, screen.json), tests/scope.lua. Skills: .claude/skills/teal for .tl files, .claude/skills/diataxis-docs and plain-writing for docs.
Also: runtime/lua/paw/views/pianoroll.lua and runtime/lua/paw/roll_clips.lua; runtime/lua/paw/views/arrange.lua (the clip label near line 544, the dim time outside the scope near line 1263); runtime/lua/paw/trackcolumn.tl; runtime/lua/paw/commands.tl (`range`) and runtime/lua/paw/ex.tl (bar numbers in ranges and arguments); runtime/lua/paw/defaults/keys.lua (`ar` near lines 277 and 752, `ie`/`ae` near lines 291 and 761); runtime/lua/paw/objects.tl; tests/arrange_scene.lua, tests/scene_parity.lua; docs/reference/grammar.md, ex.md.

Depends on: TASK-4 (V2; it merges soon: start from main after it).
Do not touch: folds (TASK-6.2, TASK-6.3), the group fold meta.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: in a group x region scope (Song › Bridge › Strings), dar deletes only the strings' clips in the region; u restores
- [ ] #2 Test: :%quantize in Song › Bridge changes only notes inside bars 17-24 of the song
- [ ] #3 Test: in Song › Bridge (bars 17-24), :tempo 96 at @19 sets the tempo at song bar 19, and :3 goes to song bar 19
- [ ] #4 Test: a clip from bar 15 to bar 19 is drawn with ‹ at the scope's start in the terminal and in the scene (tests/arrange_scene.lua); x on it removes the whole clip
- [ ] #5 Test with real keys: the piano roll opened in the scope shows only the scope's clips, and $ stops at the scope's end
- [ ] #6 Test: the track column numbers the scope's tracks from 1 and shows ›; vie selects the whole scope
- [ ] #7 narrowing.md, grammar.md, ex.md and keys.md say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
V3 built on branch worktree-agent-aae0fbe61a88ed98b, commit e1d3bb13 (main merged after it). Ex: % is the scope's time, $ its last bar, @19/@19.3 song bars in ranges, :@19, :tempo 96 at @19 (paw.tempo.place); key @19|. Arrange objects ie/ar/ir/it take only the scope (ar on the scope's rows, cut at its time). Piano roll: editable clips and context of the scope, span cut to its time (0, $ stop at its edges). Clips across a scope edge: cut_in/cut_out role props, terminal draws ‹ name and ›, paw-gui paints the same. Track column: scope sign › on row 1 (numbers were already scoped). Docs: narrowing.md, grammar.md, ex.md, keys.md, api.md. Tests: tests/scope.lua (4 new), tests/arrange_scene.lua (1 new), tutor keys.md check knows @19|. Suite plugins: all passed except the keys.md check, fixed and rerun. AC3 ':3 is song bar 19' is covered by the existing test (3| and :2), so the new test does not repeat it.
<!-- SECTION:NOTES:END -->
