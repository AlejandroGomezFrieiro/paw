---
id: TASK-168
title: 'Welcome page: the key column runs into the descriptions at 60 and 80 columns'
status: Done
assignee: []
created_date: '2026-11-22T22:44:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels: []
milestone: m-4
dependencies: []
priority: high
ordinal: 180000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-152 (2026-11-23): at 60 and 80 columns the welcome page shows 'Space Sp' then 'ace' + 'play': the keys overflow their column. tests/screens/ui/welcome.txt (branch worktree-agent-ad4f2dd1ffe304fdb) holds the broken layout today and must be blessed again with the fix. Also from TASK-152: T.expect_screen reads cell styles from the Rust Debug text of Cell in ui_frame_snapshot().cells; a small API that gives styled cells would be sturdier (do it here only if the fix needs it, else note it).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 At 60, 80 and 120 columns each key and its description are apart, by a test with real keys and a golden screen
- [ ] #2 tests/screens/ui/welcome.txt is blessed again and read by eye
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed on branch worktree-agent-a798df27f7e6cce24 (commit 2917355f, on top of the TASK-152 branch worktree-agent-ad4f2dd1ffe304fdb, merged in). runtime/lua/paw/views/arrange.lua welcome(): the description column starts after the widest key (api.str_width) plus 3; long descriptions wrap (new paw.util.wrap, moved out of help.tl); with less than 20 columns beside the keys, each description goes under its key; the area gets one Normal ground so the header rule no longer cuts the text. Tests: tests/ui.lua 'the welcome page keeps each key apart...' (goldens welcome_60/welcome_120, and a long leader set with :set leader=<C-A-S-Space> checked at 60/80/120); welcome.txt blessed again. Note: T.expect_screen still reads cell styles from the Rust Debug text; the fix did not need a styled-cell API.

Batch 6 fix (2026-11-23): branch rebased on main c386d3a4 by reverting the revert 49c532fd (eb962aee), merged TASK-188 (worktree-agent-a6c07026d44a92093, 413bcf13). Commit 766364b4: paw.ui.box now clears cell attributes (a Normal fill kept the bold of the welcome keys under the picker float: stray styles in empty rows and on the border); pick test clears paw.ui.message; tests/screens/pick/fruit.txt blessed again and read. The keybar 'i insert' and the welcome text agree with TASK-17 (i opens insert mode with m/a/r/'/f; i Enter opens the piano roll).
<!-- SECTION:NOTES:END -->
