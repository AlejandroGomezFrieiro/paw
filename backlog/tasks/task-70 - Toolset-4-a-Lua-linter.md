---
id: TASK-70
title: 'Toolset 4: a Lua linter'
status: Done
assignee: []
created_date: '2026-11-22T05:45:00Z'
updated_date: '2026-11-22T06:42:00Z'
labels:
  - teal
  - lua
  - tooling
  - lint
milestone: m-8
dependencies: []
priority: low
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
luacheck or selene for the remaining .lua files (unused variables, globals, shadowing), with a config for paw's globals (paw, vim-like APIs); a check in the suite or flake.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
luacheck with .luacheckrc (luajit, paw; REAPER/Ardour/utau-image globals; off: 212, 213, 4xx, 542, 581, 613; 311 off in tests). 523 warnings -> 0; flake check 'lua'; 520 files in ~7.5 s. Bug fixed: notation MusicXML import called rests_to() outside its scope -> a voice stopping before its barline crashed the import; test added (fails without fix). Also a global _ in engrave.lua. Removed 147 unused locals, 6 unused functions, write-only tables, unread values (calls kept as statements). One-line edits in runtime/lua/paw/views/{files,arrange,mixer,curve}.lua may meet TASK-65. Branch worktree-agent-ae41aa43fc0af79f0, commit cce50773.
<!-- SECTION:NOTES:END -->
