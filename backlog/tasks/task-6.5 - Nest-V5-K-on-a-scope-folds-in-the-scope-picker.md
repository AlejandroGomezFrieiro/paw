---
id: TASK-6.5
title: 'Nest V5: K on a scope, folds in the scope picker'
status: Done
assignee: []
created_date: '2026-11-22T09:50:00Z'
updated_date: '2026-11-22T23:53:00Z'
labels:
  - nest
  - views
milestone: m-2
dependencies:
  - TASK-6.2
parent_task_id: TASK-6
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the user finds out where he is and what a scope is. `K` on a fold or in a scope describes it, and the scope picker lists folds. This is V5 of nest.md. V2 already made `<Space>zz`, `<Space>fz` and `:scope.name`.

User-visible behavior:
- `K` on a fold, or with no item under the cursor in a scope: its path, its tracks, its bars (local and song), its meter, and whether it is folded or named: `Song › Bridge · bars 1-8 (song 17-24) · 6/8 · 12 tracks · named`.
- `<Space>zz` and `<Space>fz` also list this window's folds, marked `fold`, with the path in the preview.

Read first: Design: backlog/docs/designs/nest.md (sections 3.1 to 3.4, 3.10, 5.1, 6 and "Owner decisions, Q13-Q30": every recommended answer is accepted). The reference as V2 left it: docs/reference/narrowing.md (title "Scopes"). The code of V1 and V2: runtime/lua/paw/scope.tl (`current`, `tracks`, `span`, `path`, `breadcrumb`, `local_bar`, `song_bar`, `format`, `enter`, `widen`, `sibling`, `open`, `name`), runtime/lua/paw/layout.tl (`win.scope`, screen.json), tests/scope.lua. Skills: .claude/skills/teal for .tl files, .claude/skills/diataxis-docs and plain-writing for docs. runtime/lua/paw/scope.tl (`describe`, `saved_names`), the scope picker source (runtime/lua/paw/pick/sources.tl or where V2 put it), the `K` handler of the arrange view (runtime/lua/paw/defaults/keys.lua).

Depends on: TASK-6.2 (folds exist).
Do not touch: the fold drawing.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: znar in Bridge, then K gives the path, the local and song bars and the meter
- [ ] #2 Test: K on a folded group gives its name, its tracks and 'folded'
- [ ] #3 Test: <Space>zz lists the window's folds marked fold; choosing one enters it
- [ ] #4 narrowing.md says it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
K on a closed fold or in a scope (no clip under the cursor) describes it before the track: 'Song › Bridge · bars 1-8 (song 17-24) · 6/8 · 7 tracks · named'; a fold adds folded/open. <Space>zz/<Space>fz list the window's folds (marked fold, path and contents in the preview); choosing one enters it. New: paw.scope.describe(s, extra), describe_fold, of_fold; paw.folds.closed_at; arrange view describe set in scope.tl. Docs: narrowing.md. Tests: tests/scope.lua (K in a region scope), tests/folds.lua (K on a folded group, <Space>zz lists folds). Branch worktree-agent-a444b356c3e8b97a0, commit 948209ab. No Rust change.

Merged to main (batch 4, 2026-11-23): dev build, apidoc regenerated, nextest paw-core/engine/tui/mcp (400) and the full suite with plugins passed. At the merge: vzoom.tl's Paw record names the keymap (TASK-125 took it out of partial.Paw).
<!-- SECTION:NOTES:END -->
