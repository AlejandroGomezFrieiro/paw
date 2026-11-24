---
id: TASK-71
title: 'Toolset 5: language servers for editing paw''s code'
status: Done
assignee: []
created_date: '2026-11-22T05:45:00Z'
updated_date: '2026-11-22T06:42:00Z'
labels:
  - teal
  - lua
  - tooling
  - lsp
milestone: m-8
dependencies: []
priority: low
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
teal-language-server and lua-language-server in the dev shell with configs (tlconfig.lua, .luarc.json from runtime/types), so editors (the owner uses Neovim) get completion and types for paw's API; a short contributor doc.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
.luarc.json (LuaJIT, runtime/types, global paw); tlconfig.lua already serves teal-language-server 0.3.0. Tried: Teal server completes paw.* (149) and util.* and hovers types; LuaLS hovers paw.option after loading. How-to docs/how-to/configure-an-editor-for-paws-code.md + test 'guide: configure an editor for paw's code'; about-teal.md section on the tools. Limitation: extension lua/ dirs not in tlconfig include_dir. Branch worktree-agent-ae41aa43fc0af79f0, commit e0ca4653.
<!-- SECTION:NOTES:END -->
