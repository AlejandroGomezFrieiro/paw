---
id: TASK-78
title: 'Startup profiling: --startuptime and :profile'
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-22T13:32:00Z'
labels:
  - performance
  - tooling
milestone: m-3
dependencies: []
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: show where the start time goes, and where the Lua time goes in a session, as Neovim does with `--startuptime` and `:profile`.

User-visible behavior:
- `paw --startuptime FILE` writes one line for each phase of the start: the Rust start, the Lua runtime, each module of runtime/lua/paw that `init.lua` requires, the configuration (`init.lua` of the user), each extension, the project load, and the first frame. Each line gives the clock since the start, the time of the item alone, and the time with what it required: `  12.400  0.800  1.900: require paw.harmony`. The format is that of Neovim, so that the same tools read it.
- `:profile start [file]` starts LuaJIT's sampling profiler (`jit.profile`) in the kernel; `:profile stop` stops it and shows the 30 Lua functions that took the most time in a list (the quickfix list, with file and line). With a file, it also writes the folded stacks for a flame graph.
- `:profile` alone says whether the profiler runs.

Read first:
- crates/paw-tui/src/args.rs (clap arguments) and crates/paw-tui/src/main.rs (the start order); crates/paw-gui/src/args.rs (the window takes the same option).
- runtime/lua/paw/init.lua (the requires), runtime/lua/paw/ext.lua (extension loads), runtime/lua/paw/loading.lua (project load).
- bench/startup.sh, bench/profile/drive.py (`startup`, and `--luaprof` near line 343: how it uses jit.profile), bench/profile.md.
- docs/reference/programs.md (the options of the paw command), docs/reference/quickfix.md.
- TASK-3 (lazy-loaded extensions, m-5) uses this output to measure.

Depends on: nothing.
Do not touch: the order of the start (only measure it); TASK-3's lazy loading.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test (tests/core.lua or a new tests/startuptime.lua): paw --startuptime FILE --clean --no-plugins --audio null -c 'qa!' writes a file with a line for paw.harmony, one for the first frame, and clocks that grow
- [ ] #2 With an extension loaded (tests/fixtures), the file has a line for it with its own time
- [ ] #3 Test: :profile start, a Lua loop of 50 ms, :profile stop gives a quickfix list whose first entry is the loop's function
- [ ] #4 --startuptime adds less than 2 ms to a start (bench/startup.sh, median of 10, spread given)
- [ ] #5 docs/reference/programs.md and docs/reference/ex.md (or the page that lists :profile) document both; bench/profile.md says how to use them; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a1c7300cde2da33bb (commits dc82129d, ef44c09e, merge of main f82365cb). paw --startuptime FILE writes Neovim-format lines (clock, self+sourced, self) for Rust steps, each module that require loads (paw/startuptime.tl wraps require until the first frame), each extension (paw.ext.load), the user's init.lua, the project load, -e/--keys, and the first frame (or 'the script starts' with -l). New: crates/paw-core/src/startuptime.rs, paw.api.startup_enter/startup_leave/startup_timed. :profile start [file] / stop / alone in runtime/lua/paw/profile.tl (jit.profile, top 30 Lua functions in the quickfix list with paw://lua/<file>#<line> addresses, folded stacks to the file). Tests: tests/startuptime.lua (3) and a Rust unit test. Overhead measured under external load: median of 10, +0.6 ms wall (53.0 vs 53.6 ms, spread 41 to 79 ms).
<!-- SECTION:NOTES:END -->
