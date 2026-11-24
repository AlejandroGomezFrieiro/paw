---
id: TASK-67
title: 'Toolset 1: cyan check replaces tools/tlcheck.sh'
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
priority: medium
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
One process for all .tl files with tlconfig.lua (per-extension include dirs); same errors; the suite and nix flake check use it; measure time before/after.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
tools/tlcheck.sh = one cyan check over the 94 .tl files (each extension's lua/ on the path; redeclaration warning of the documented local paw = (_G as ...).paw off; paw.lang.check in the suite still counts it). Time: 6.9-7.5 s wall / 5.8-6.4 s user vs 104-127 s wall / 90-109 s user for tl check per file (measured under external load). Same 5 errors + 2 warnings on two files broken on purpose (old printed util.tl's 94 times). cyan patched in nix/lua-tools.nix (report_env_results short-circuit). Flake teal check uses it. Branch worktree-agent-ae41aa43fc0af79f0, commit 7af5c33f.
<!-- SECTION:NOTES:END -->
