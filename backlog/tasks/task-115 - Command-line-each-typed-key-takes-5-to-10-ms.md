---
id: TASK-115
title: 'Command line: each typed key takes 5 to 10 ms'
status: Done
assignee: []
created_date: '2026-11-22T13:03:00Z'
updated_date: '2026-11-22T18:00:00Z'
labels:
  - performance
milestone: m-3
dependencies: []
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-79 (paw.opt.budget_ms = 5, bench/profile/run.sh keys on project.lua, measured under external load, load average 70 to 94).

When you type ':help' on the command line, the budget check names 'the key h', 'the key e', 'the key l' and 'the key p', 5 to 11 ms of wall time each, in 3 of 3 runs. Each key of the command line gives more than the budget. The cause is not known: find it with bench/profile/run.sh repeat --keys ':,h,e,l,p,\x1b' --luaprof (completion, the hint list, or the redraw of the command line are the first suspects).

Read first: runtime/lua/paw/views/cmdline (the command line), runtime/lua/paw/complete.tl, bench/profile.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With budget_ms = 5, typing a command name writes no slow warning at a load average under 20
- [ ] #2 The completion tests pass unchanged
- [ ] #3 With paw.opt.budget_ms = 5 on bench/profile/project.lua (64 tracks, 50000 notes), typing ':help' names no slow key and no slow 'drawing the screen' for the prompt keys
- [ ] #4 Each key of the command line (h, e, l, p) reaches its first frame under 5 ms median, measured with min and max under external load (load average reported)
- [ ] #5 A key typed in the plain ':' line draws only the line and the list again (a live frame), not the whole screen; a range or a match typed still draws the whole frame (the views show it)
- [ ] #6 The completion and hint-list tests pass unchanged; a new test with real keys guards the live frame and the full frame for a range
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a0810eccf156a8983. The command line and its candidate list are live parts; a key in a plain prompt calls api.ui_redraw_line (live frame + windows told via ui_redraws) instead of a whole frame. keymap.dispatch skips its own ui_redraw then (keymap.screen_kept). ex.preview asks for a whole frame only when a range/match is lit. First frame per key 10-14 ms -> 4.2 ms median under load 6.5 (min 3.5, max 20). Test in tests/cmdline_rules.lua.
<!-- SECTION:NOTES:END -->
