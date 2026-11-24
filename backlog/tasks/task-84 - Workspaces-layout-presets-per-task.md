---
id: TASK-84
title: 'Workspaces: layout presets per task'
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - ux
  - views
milestone: m-2
dependencies:
  - TASK-4
priority: low
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: as Blender's workspaces, the user switches between named screens for a task (record, edit, mix, score) with one key. Each workspace keeps its tabs, splits and views as the user left them.

Today: `:layout save <name>` and `:layout <name>` write and put back the tabs and windows (state_dir/layouts/), and `paw.layouts.<name>` in init.lua defines layouts (docs/reference/windows.md, "Layouts"). The project's screen.json keeps the windows of each seat. Workspaces build on this; they are not a second system.

User-visible behavior:
- A new leader domain `<Space>w` (free today): `<Space>ww` a picker of workspaces; `<Space>wr` record, `<Space>we` edit, `<Space>wm` mix, `<Space>wn` score (notation); `<Space>ws` save the screen as a workspace (asks for the name).
- `:workspace <name>` switches. paw keeps the tabs of the workspace that you leave in memory, so that you come back to it as you left it.
- Four default workspaces, as layouts in the defaults: record (arrange with the armed track and the mixer), edit (arrange and piano roll), mix (mixer and device panel), score (notation). `init.lua` can change or add them through `paw.layouts`.
- `:workspace.save <name>` keeps it for the user (state_dir/layouts); `:workspace.save! <name>` keeps it in the project's screen.json, so that the project opens with it.
- The status line shows the workspace's name (a status component, on by default).

Read first: runtime/lua/paw/layout.tl ("Saved layouts", near lines 2427 to 2700: `M.save`, `M.layouts`, the layouts folder; screen.json), docs/reference/windows.md (Layouts), docs/reference/keys.md (the leader domains table), docs/how-to/arrange-your-screen.md, tests/leader_hints.lua.

Depends on: TASK-4 (V2 changes layout.tl and screen.json; start after it merges).
Do not touch: scopes in screen.json.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test with real keys: <Space>wm shows the mixer workspace; <Space>we comes back to the edit workspace with its tabs and cursor as left
- [x] #2 Test: <Space>ws with a name, then the picker <Space>ww lists it; it is in state_dir/layouts
- [x] #3 Test: :workspace.save! keeps it in the project's screen.json, and the project opens with it
- [x] #4 Test: the status line shows the workspace name; tests/leader_hints.lua lists the <Space>w domain
- [x] #5 windows.md, keys.md (leader domains) and arrange-your-screen.md say it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-afd437004b19b13be (commits de952c7a, merge 84a52135, b3af4f61). New runtime/lua/paw/workspace.tl: :workspace, :workspace.save, :workspace.save!, picker 'workspaces', status component 'workspace'; <Space>w domain in defaults/keys.lua; default layouts record/edit/mix/score in defaults/views.lua. layout.tl: layout_spec (saved file now wins over paw.layouts), project_saving keeps other fields of screen.json. Tests in tests/guides_screen.lua (3) and tests/leader_hints.lua. Docs: windows.md (Workspaces), keys.md, status-line.md, arrange-your-screen.md, state-files.md, lua-views.md. Not done: record workspace does not move the cursor to the armed track.

Follow-up a5d09cae: record workspace moves the cursor to the first armed track (paw.workspace.on_enter); :workspace.save! calls the new kernel function paw.api.project_mark_changed (Rust: paw-core api/project.rs, session/project.rs). Needs a build: the modified assertion in the :workspace.save! test fails with the old shared binary.

Merged to main in batch 16 (cd367da1); full suite and checks passed after three merge fixes.
<!-- SECTION:NOTES:END -->
