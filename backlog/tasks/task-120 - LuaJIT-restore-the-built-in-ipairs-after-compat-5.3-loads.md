---
id: TASK-120
title: 'LuaJIT: restore the built-in ipairs after compat-5.3 loads'
status: Done
assignee: []
created_date: '2026-11-22T17:29:00Z'
updated_date: '2026-11-22T19:09:00Z'
labels:
  - performance
  - lua
milestone: m-3
dependencies: []
priority: medium
ordinal: 132000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-77.1: compat-5.3 (runtime/lua/compat53/module.lua:180-195, loaded by paw/compat.tl) replaces the global ipairs with a Lua function for all of paw. With short inner loops it keeps LuaJIT traces slow. Restore the built-in ipairs after compat53 loads, after checking that no code relies on __index in ipairs (grep for ipairs over proxy tables and records with __index). Measure a frame and the chord reading before and after.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No code relies on ipairs following __index (listed in the notes, with the grep used)
- [ ] #2 The built-in ipairs is in place after paw starts (a test)
- [ ] #3 A frame and the chord reading measured before and after, with spread, under external load; the full suite passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a395643f2fb7be61f, commit 6c922446 (+ merge of main). compat.tl saves the built-in ipairs before require(compat53) and restores it after. Audit: grep -rn __index over runtime extensions tests tools crates (about 70 sites: classes, option/state/project proxies, notation delegation tables) plus a temporary instrumented ipairs (logs any ipairs over a table whose items come through __index or whose metatable has __len, or over a non-table) during the full suite plugins run: the only hit was the new test. Nothing relies on it. Measured under external load (load 50-60), 6 interleaved pairs: no measurable difference (instructions per frame ~24.3M both, per chord reading ~870M both); wall time noise larger than any difference. Full suite plugins: all passed.
<!-- SECTION:NOTES:END -->
