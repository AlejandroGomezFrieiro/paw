---
id: TASK-19
title: 'Pencil: ~ tie, <C-r> register, C strum directions, <Tab> snippets'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-22T12:52:00Z'
labels:
  - insert-mode
milestone: m-4
dependencies: []
priority: medium
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the owner decides on the pencil proposals that are not yet approved. Then each approved key is built with a test.

Built (owner-approved): C strum, a{name} articulation, <C-n>/<C-p>, mr, e{cc}.

Owner question: which of these does the pencil get? My recommendation is after each.
1. `p` as a sustain pedal key. Recommended: no. `es` already writes CC64, and `p` means put in normal mode.
2. `~` tie or glide to the next note (lengthens the note to the start of the next one). Recommended: yes, as a tie; notation's insert mode uses `~` for a tie too.
3. `<C-r>{reg}` puts a register at the pencil, as in Vim's insert mode. Recommended: yes.
4. `<Tab>` expands a snippet at the pencil (docs/reference/snippets.md). Recommended: yes, if the snippet engine already works in the piano roll; else later.
5. A `bend_ramp` option (the shape of a drawn bend). Recommended: not now.
6. `C` strum up and down, and a strum value typed in the picker. Recommended: yes.

After the answer: each approved key has a test with real keys in tests/drawinsert.lua, and rows in docs/reference/insert-mode.md and docs/reference/piano-roll.md.

Read first: runtime/lua/paw/roll_draw.tl (the pencil keys, `M.key`), docs/reference/insert-mode.md, docs/reference/snippets.md, docs/reference/key-rule.md.

Depends on: the owner's answer.
Do not touch: anything until the owner answers.

Size: S after the answer (each key S).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The owner's answer is written in this ticket's notes
- [ ] #2 Each approved key has a test with real keys in tests/drawinsert.lua
- [ ] #3 insert-mode.md and piano-roll.md list each approved key; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner answer: ~ tie, <C-r>{reg}, C directions+typed gap, <Tab> snippets (engine works in the roll: built); no p, no bend_ramp. Built on branch worktree-agent-aff1f69160d4f53db, 1 commit. Strum picker words: up/down/updown, @N 64ths. Tests in tests/drawinsert.lua; rows in docs/reference/piano-roll.md, options.md.
<!-- SECTION:NOTES:END -->
