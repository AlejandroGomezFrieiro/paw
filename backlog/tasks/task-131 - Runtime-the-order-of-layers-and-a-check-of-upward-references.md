---
id: TASK-131
title: 'Runtime: the order of layers, and a check of upward references'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels:
  - architecture
  - lua-review
milestone: m-10
dependencies: []
priority: medium
ordinal: 143000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Write the layers of the runtime in an internal page. Add a Lua script in `tools/` that reads `require` and `paw.x` references of each module, prints the graph, and fails on an upward reference that is not on its allow-list. Run it in the suite.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L7 and its proposal P9.

Overlaps: TASK-26.
Dependencies: none.

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the page and the script exist
- [ ] #2 the allow-list has a count, and the check fails on a new upward reference
- [ ] #3 the graph output can feed TASK-26
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a27352cf7687c0ba1, commit 5e094427 (main had no new commits at report time). tools/layers.txt (layers: kernel, data, project, screen, input, views, frontends, boot), tools/layers.lua (check, graph, counts; plain LuaJIT), tools/layers-allowed.txt (303 upward names on 195 lines), tests/layers.lua (suite), flake check layers, internal page .claude/skills/paw-code/layers.md. Count = distinct names that one module reads of another. Biggest upward targets: paw (init.lua timers/try/command/state, 67), paw.frontend (53), paw.ui (48, mostly notify), paw.keymap (20), paw.commands (17). When TASK-125/128/77.x land: new modules need a line in tools/layers.txt; moved references move their count in tools/layers-allowed.txt; the messages name the lines.

2026-11-23: merged f1b087ae (batch 7) as d4bb056a and fixed the 32 problems. New modules have layers. paw.edit imports Register from paw.keymap.registers, which is in the project layer. paw.ext no longer reads frontend.bands or roll_draw.keys: init.lua adds those two registries. A module's own require counts only when it is the only name. Teal casts are read. The allow-list is 281 names on 198 lines.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
