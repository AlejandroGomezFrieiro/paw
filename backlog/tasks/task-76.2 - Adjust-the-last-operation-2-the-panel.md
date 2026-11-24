---
id: TASK-76.2
title: 'Adjust the last operation 2: the panel'
status: Done
assignee: []
created_date: '2026-11-22T09:47:00Z'
updated_date: '2026-11-22T15:36:00Z'
labels:
  - ux
  - editing
milestone: m-4
dependencies:
  - TASK-76.1
parent_task_id: TASK-76
priority: medium
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: a small panel shows the parameters of the last adjustable command, and the result changes live while the user changes a value. The panel is one scene, so the terminal and the window show the same panel.

User-visible behavior:
- `<leader>.` opens the panel after an adjustable command (TASK-76.1 opened the command line; the panel's `:` now opens that command line).
- `j` `k` choose a parameter. `+` `-` and `<C-a>` `<C-x>` change its value by its step, as the key rule says. A count multiplies the step. `<CR>` on a parameter types a value.
- Each change runs the command again through `:adjust` (TASK-76.1): it is still one undo step. Changes that come quickly (a key held) settle: paw runs only the last one after 50 ms.
- `Esc` closes the panel and keeps the result. `u` after it undoes the whole command.
- The panel says the command and its range: `Quantize · 48 notes`.

Read first:
- The commit of TASK-76.1.
- docs/explanation/about-scenes.md (one view, two frontends), docs/reference/key-rule.md.
- A float view to copy: the notation popovers (extensions/notation/lua/notation/popover.lua) and runtime/lua/paw/ui.tl (floats).
- tests/scene_parity.lua (the same scene in both frontends) and the paw-gui tests.

Depends on: TASK-76.1.
Do not touch: the commands of TASK-76.1 (only the panel and the key).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: :quantize 1/16 strength=100, <leader>., j to strength, - twice: strength is 90 and the notes moved accordingly; the undo tree has one state for all of it
- [ ] #2 Test: Esc closes the panel and keeps the result; u then returns to the notes before :quantize
- [ ] #3 Test: five quick + presses run the command once after the settle (count the runs)
- [ ] #4 tests/scene_parity.lua (or a paw-gui test) shows the same panel in the window frontend; cargo test --release -p paw-gui passes
- [ ] #5 Each change on 1 000 notes stays under 100 ms of kernel time (bench/profile repeat)
- [ ] #6 keys.md and ex.md describe the panel; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a26b1dc2cdb8480b9, commit ead59e62 (merged with main d76933cc). Panel: runtime/lua/paw/views/adjust.tl (Teal float view, modal); commands.panel() and commands.about() in commands.tl; <Space>. opens it; docs keys.md (The adjust panel) and ex.md; tests/adjust.lua. Full suite: only the strict teal check failed (shadowed paw), fixed; adjust, teal, scene_parity pass after. paw-gui tests pass. 1000 notes: adjust median 11.8 ms (min 8.1, max 37.3), shared machine.
<!-- SECTION:NOTES:END -->
