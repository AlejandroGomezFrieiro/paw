---
id: TASK-4
title: 'Nest V2: scopes per window and free movement'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T09:45:00Z'
labels:
  - nest
  - views
  - keys
milestone: m-2
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
zn as an operator (znar, znag, znit, block), znn innermost, zw/zW, ]z [z siblings, jump list across scopes, <Space>z domain (zz picker, zs/zv/zt split/vsplit/tab, names). Owner: views and subprojects must be reachable freely. Design: backlog/docs/designs/nest.md (V2). V1 is merged.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
V2 done on branch worktree-agent-a10ec4f805d66fb66 (commits 302ef1ae, merges ee7dcad1 and 27f308d3 with main incl. TASK-5). Scopes belong to arrange windows (win.scope stack; other views follow the tab's arrange window); views read the drawn window's scope (paw.ui.drawing_win) so terminal and scene agree; tab named after its window's scope; screen.json keeps stacks + named scopes. Keys: zn operator (znar/znag/znit/Visual zn), znn innermost (in a region: the region inside), zw, zW, ]z [z siblings (regions of the same parent via paw.markers tree, groups in same group, tracks of parent, a block's next stretch), jumps keep scopes (<C-o>/<C-i>), <Space>z domain (zz picker = <Space>fz with regions as a tree, zs/zv/zt, zn name). Not done (later parts): <CR> into folds or nest clips (V4/S1), K on a scope (V5), folds as view state (V4). Full suite plugins: all passed.
<!-- SECTION:NOTES:END -->
