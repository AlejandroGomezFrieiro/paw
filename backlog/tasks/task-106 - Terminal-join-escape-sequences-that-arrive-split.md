---
id: TASK-106
title: 'Terminal: join escape sequences that arrive split'
status: Done
assignee: []
created_date: '2026-11-22T10:55:00Z'
updated_date: '2026-11-22T12:19:00Z'
labels:
  - tui
  - web
milestone: m-9
dependencies: []
priority: high
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In BrowserPod (TASK-54) the tty delivers ESC alone, then the rest (1b, then 5b 41), so crossterm reports Esc, '[', 'A': arrows, Alt, F-keys, mouse and paste break. Fix in paw-tui's terminal.rs: after a lone ESC, wait a short time (e.g. 10 to 25 ms, an option like Vim's ttimeoutlen) for the rest of the sequence before reporting Esc. Helps slow SSH links too. Test with a fake tty that splits sequences.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a2d726a473c03cc2b; keys.rs Joiner in paw-tui, PAW_TTIMEOUTLEN default 15 ms; docs/reference/programs.md
<!-- SECTION:NOTES:END -->
