---
id: TASK-66
title: 'Toolset 0: evaluate and package the Teal/Lua tools'
status: Done
assignee: []
created_date: '2026-11-22T05:45:00Z'
updated_date: '2026-11-22T06:42:00Z'
labels:
  - teal
  - lua
  - tooling
milestone: m-8
dependencies: []
priority: high
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Evaluate cyan (github.com/teal-language/cyan), cerulean (github.com/efredriksson/cerulean), tested (github.com/FourierTransformer/tested), StyLua, luacheck/selene, teal-language-server and lua-language-server for paw: maturity, Teal version compatibility with our embedded tl, LuaJIT/5.1 target, speed on ~450 files, nixpkgs availability (package missing ones in the flake). Output: backlog/docs/designs/teal-toolset.md with a recommendation per tool and a plan; the tools added to the dev shell on a branch.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Evaluated by running each tool on the tree; full write-up: backlog/docs/designs/teal-toolset.md. Verdicts: cyan adopt (patched: 0.4.1 stops reporting after the first erroring file); teal-language-server adopt 0.3.0 (nixpkgs 0.1.3 gives nothing on paw); lua-language-server adopt for editing; luacheck adopt (clean, found a MusicXML import bug); selene reject (no LuaJIT std, cannot parse goto/ULL); StyLua and cerulean packaged, no reformat (style mismatch); tested not adopted. Dev shell gains cyan, teal-language-server 0.3.0, cerulean 1.9.2 (nix/lua-tools.nix, pinned), lua-language-server, stylua, luacheck. Branch worktree-agent-ae41aa43fc0af79f0, commit 56cf8ca6.
<!-- SECTION:NOTES:END -->
