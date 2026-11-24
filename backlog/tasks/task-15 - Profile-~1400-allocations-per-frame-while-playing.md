---
id: TASK-15
title: 'Profile: ~1400 allocations per frame while playing'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T15:36:00Z'
labels:
  - performance
milestone: m-3
dependencies:
  - TASK-88
priority: medium
ordinal: 2500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: while the song plays, the kernel makes about 1 400 allocations per frame. Make it fewer than 200 per frame, with no change of what the user sees.

Half of the allocations come from mlua's `LuaString::to_str` (an `Rc` for each string argument) in the screen API (`text`, `style_of`). The rest are Lua tables and closures that the views make on each frame.

What to do:
- Style names become integer ids: the theme gives an id once for each style name, and the screen API takes the id. Text goes in as borrowed bytes (`LuaString::as_bytes`), not as an owned string.
- One transport snapshot for each frame, shared by the status line, the ruler and the views (today each one calls the API).
- Keep the widths of the status line components until their text changes.
- Move closures out of the draw loops of the arrange view, the status line and the track column.

Read first:
- bench/RESULTS.md, 2026-11-21 profile, item 5 of "What is left".
- bench/profile.md: `--wrap "heaptrack -o <file>"`, and the two runs with different `--secs` that give the steady state (`heaptrack_print -f <long> -d <short>`).
- crates/paw-core/src/api/screen.rs (`text`, `style_of`), crates/paw-core/src/grid.rs, crates/paw-core/src/scene.rs.
- runtime/lua/paw/frontend.tl (live frames), runtime/lua/paw/statusline.tl, runtime/lua/paw/theme.tl, runtime/lua/paw/trackcolumn.tl, runtime/lua/paw/views/arrange.lua.
- .claude/skills/rust-skills (mlua, no allocation in hot paths) and .claude/skills/teal for each .tl file.

Depends on: TASK-88 (it changes the same draw loops of the arrange view; TASK-14 is merged). Read the TASK-14 merge (a36b7e14) first: the clip list is lean now.
Do not touch: `clip_list` (done in TASK-14), the engine.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 heaptrack on bench/profile/run.sh play (steady state, two runs) shows fewer than 200 allocations per frame on bench/profile/project.lua; bench/RESULTS.md gets the before and after numbers with their spread
- [ ] #2 The frames do not change: tests/frames.lua, tests/scene_parity.lua and tests/arrange_scene.lua pass with no change of their expected output
- [ ] #3 The screen API takes style ids; its doc comments say so, and docs/reference/api.md is generated again with tools/apidoc.lua (not edited by hand)
- [ ] #4 The full Lua suite, cargo test --release -p paw-core and cargo test --release -p paw-gui pass; tools/tlcheck.sh passes with no new any
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a417b4b6e5931d609, commits b8d67850 (the change), 3bfba80a (RESULTS.md), 76a7feed (test fix), merges c2f94745 and bc942e60 (main up to cf15cd12). Allocations per frame while playing (heaptrack, 30 s minus 10 s, 3 interleaved pairs, measured under external load, load 40-59): 1467 (1449-1487) -> 111 (93-129). Kernel instructions per frame 3.22 M (3.19-3.36) -> 2.33 M (2.30-2.36), 5 pairs. Kernel CPU 8.4% -> 6.2%. What: paw.api.hl_id and style ids in grid_text/grid_fill; LuaText reads text from the Lua stack (no Rc per string); TransportView/EngineView/BlockTimes typed; grid pools live-part buffers; paw.ui.transport() one per frame; layout.find/find_id with no lists or closures; status line keeps segments and widths; arrange playhead spans kept, one lane sampler; trackcolumn comparators hoisted. Test: tests/viewwindow.lua.
<!-- SECTION:NOTES:END -->
