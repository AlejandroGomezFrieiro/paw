---
id: TASK-83
title: 'Command-line window (q: and q/)'
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels:
  - ux
  - editing
milestone: m-4
dependencies: []
priority: low
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: as Neovim's command-line window, the past `:` commands and `/` searches open as a text buffer. The user edits a line and runs it again with Enter. Useful for `:g` and other long commands.

User-visible behavior:
- `q:` opens the `:` history and `q/` the `/` history in a split at the bottom, oldest first, the cursor on an empty last line. (`q` starts a macro; `q:` and `q/` are the two exceptions, as in Vim.)
- `<C-f>` in the command line opens the window with the text typed so far on the last line.
- The buffer is a text buffer: every Normal and Insert key of text buffers works. `<CR>` runs the line under the cursor, in the window that was in front, and closes the window. `:q` or `<C-c>` close it without running anything.
- Changes to the lines do not change the history; the line run is added to the history.

Read first: runtime/lua/paw/views/cmdline.lua (histories by name), runtime/lua/paw/textbuf.tl and docs/reference/lists-edited-as-text.md (text buffers), runtime/lua/paw/keymap.lua (the macro key `q`), docs/reference/cmdline.md.

Depends on: nothing (after TASK-81 the history also holds the commands of earlier sessions).
Do not touch: the history storage (TASK-81).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test with real keys: :echo 1, :echo 2, then q: shows both lines; k, then <CR> runs echo 2 and closes the window
- [ ] #2 Test: edit a line in the window (cw), <CR> runs the edited line and adds it to the history
- [ ] #3 Test: q/ shows the searches; <CR> on one searches it
- [ ] #4 Test: <C-f> at the command line opens the window with the typed text on the last line
- [ ] #5 Test: qa still starts a macro in register a
- [ ] #6 cmdline.md and keys.md document it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a6c611ce53e62bb0b, commit 7e5eddf4 (no merge of main was necessary: main did not move after the base fd0e1f0b). New module runtime/lua/paw/cmdwin.tl: q: and q/ open the history of : or / as a text buffer (kind history, paw://history/<name>) in a window along the bottom, 7 rows. Ctrl-f in any prompt with a history opens it with the typed text on the last line. Enter in normal mode runs the line through the prompt that opened the window (views/cmdline.lua detach and resume), in the window that was in front. :q and Ctrl-c close it. Generic textbuf change: a kind with 'scratch' (the message of :w) is never written, and :q closes it with its changes. A kind without a gutter no longer draws signs over its text. Tests: tests/cmdwin.lua (6). Docs: cmdline.md, keys.md, lua-views.md, api.md (generated). Not done: Enter in insert mode splits the line, as in other text buffers (Vim runs the line).
<!-- SECTION:NOTES:END -->
