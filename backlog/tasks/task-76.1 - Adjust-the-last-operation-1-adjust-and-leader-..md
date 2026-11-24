---
id: TASK-76.1
title: 'Adjust the last operation 1: :adjust and <leader>.'
status: Done
assignee: []
created_date: '2026-11-22T09:47:00Z'
updated_date: '2026-11-22T12:51:00Z'
labels:
  - ux
  - editing
  - undo
milestone: m-4
dependencies: []
parent_task_id: TASK-76
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: after a command with parameters, the user changes its parameters and paw does the command again in place of its undo step, not as a new step. This is Blender's "adjust last operation", for the keyboard first.

User-visible behavior:
- A command declares the parameters that can change after it ran, in its options: `paw.command(name, fn, { adjust = { { name = "grid" }, { name = "strength", min = 0, max = 100, step = 5 } } })`.
- `:adjust grid=1/8 strength=60` (or positional, `:adjust 1/8`) does the last command again with these parameters merged into its first ones: paw goes back to the state before it, runs it again on the same range, items and selection, and the new state takes the place of the old one in the undo tree. `u` then returns to the state before the command.
- `<leader>.` opens the command line with `:adjust ` and the current values, with completion of the names and values. (`.` repeats the last change; `<leader>.` adjusts it.)
- After `:adjust`, `.` repeats the command with the adjusted parameters.
- When the last change cannot be adjusted: `the last change (Delete) has nothing to adjust`. After `u`, or when the current state is not the newest one: `adjust works on the last change`.
- Commands that adjust in this ticket: `:quantize` (grid, and a new `strength` from 0 to 100, default 100), `:transpose` (semitones), `:clip.fade` (in and out lengths), and musicops' humanize when it is a command. Others follow later, each in its own ticket.

Read first:
- runtime/lua/paw/commands.tl (`define`, `Options`, `run`, `exec`, the `command.post` event with `Ran`).
- runtime/lua/paw/ex.tl: `quantize` (near line 2317), `transpose` (near line 2333); runtime/lua/paw/defaults/clips.lua: `clip.fade` (near line 539).
- crates/paw-core/src/history.rs (states, children, `redo`), crates/paw-core/src/session/undo.rs (`undo_goto`, `undo_discard` near line 248, `undo_join`, `undo_label`), crates/paw-core/src/api/undo.rs.
- runtime/lua/paw/keymap.lua (`last_change`, how `.` replays).
- docs/reference/ex.md, docs/reference/lua-commands.md, docs/reference/key-rule.md, docs/reference/keys.md.
- AGENTS.md rule 6 (one action is one undo step and says what it did).

Depends on: nothing.
Do not touch: the panel (TASK-76.2).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: select notes, :quantize 1/16, then <leader>. and change the value to 1/8 and Enter: the notes are on the 1/8 grid; the undo tree has one new state since before :quantize; u returns to the notes before it
- [ ] #2 Test: :quantize 1/16 strength=100, then :adjust strength=50 moves each note half the way
- [ ] #3 Test: :transpose 12, then :adjust 7 gives the notes 7 semitones above the first ones, in one undo step
- [ ] #4 Test: :adjust after a change with no adjust gives the message and changes nothing; after u it gives 'adjust works on the last change'
- [ ] #5 Test: . after :adjust repeats the adjusted command on the next selection
- [ ] #6 One :adjust of :quantize on 1 000 notes in bench/profile/project.lua takes less than 100 ms of kernel time (bench/profile repeat; number in the commit message)
- [ ] #7 ex.md, lua-commands.md (opts.adjust) and keys.md (<leader>.) document it; docs/reference/api.md is generated again; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-af7532d5c5a36e6de (commits b0d2dffe, a keys-rule follow-up, then main merged). :adjust + <Space>. via commands.tl (adjust option, paw.commands.params/adjust/adjusting), Rust undo_adjust/undo_adjust_cancel (History::set_label), keymap.repeat_as. quantize (grid, strength), transpose (semitones), clip.fade (in, out) adjust. musicops humanize not done: it is an operator and musicops.apply takes free-form parameters. Bench: 1000 notes quantize adjust 11-35 ms CPU (5 runs, loaded machine). Tests: tests/adjust.lua.
<!-- SECTION:NOTES:END -->
