---
id: TASK-152
title: 'Tests: golden files for the terminal screen'
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies: []
priority: high
ordinal: 164000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/testing-practices.md, practices L2 and U1, gap G1, ticket BT4, rank 1. Owner, 2026-11-22: yes, golden files for the terminal screen.

Tests search the screen for a string (`screen():find(...)`), so a wrong layout that still holds the string passes. The terminal is the main frontend.

What to do: add `T.expect_screen(name, width, height, opts)` to `tests/suite.lua`. It takes `api.ui_snapshot`, adds style ids in the manner of Neovim (`{1:text}`), and compares with `tests/screens/<file>/<name>.txt`. With `PAW_BLESS=1` it writes the file. On a failure it prints a diff, the path and how to bless. Move 10 tests that check layout with `find()` to it (statusline, piano roll, mixer strip, help, picker, arrange). Keep each grid small. `find()` stays for "this text exists". When the clock ticket is done, `T.expect_screen` settles first; until then, use it only for views that draw at once.

Read first: backlog/docs/designs/testing-practices.md, sections 2.3 (L2), 2.5 (U1), 4 (rank 1), 5.2, 6 (BT4).

Overlaps: tests/scene_parity.lua (keep it: it checks the window against the terminal; this checks the terminal against a file).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A missing golden file fails, and the message tells how to bless
- [ ] #2 A golden file that no test uses fails the runner
- [ ] #3 The 10 moved tests pass, and each fails when a column of its view moves by one cell (checked once, named in the commit)
- [ ] #4 The skills .claude/skills/lua-testing and .claude/skills/rust-testing name the new helpers and commands in the same commit.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
T.expect_screen(name, w, h, opts) in tests/tools/golden.lua (suite.lua: one dofile line, one call after the run, golden txt ignored by the left-files check). Style ids {n:text} with a legend; opts.rows/cols/styles; PAW_BLESS=1 writes and removes unused. Missing file fails with the bless command; unused golden fails 'every golden screen has a test' (only for test files whose every test ran to the end). Converted 7 tests / 8 files (ui welcome+one_track, too_small, chips, ascii, status_narrow; pick fruit; mixer_strip outputs) as examples per orchestrator; the rest of the 10 goes to TASK-149. Each fails on a one-cell column move (checked once). Docs: run-the-tests.md, lua-testing, rust-testing. Found: the welcome page's key column overlaps its descriptions (Space Space/play) at 60 and 80 columns; blessed as is. Branch worktree-agent-ad4f2dd1ffe304fdb, commits 75f9f6ff, merge adcec3f8.
<!-- SECTION:NOTES:END -->
