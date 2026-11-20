# How to undo, and return to an earlier state

<!-- tags: undo-guide -->

This guide shows you how to undo a change, and how to return to any
earlier state of the project. paw keeps every state, also the states that
you undid and then changed.

## Undo and redo

- Press `u` to undo the last change. The message says what it undid, for
  example `undid Move clips later`.
- Press `<C-r>` to redo it.
- A count undoes more: `3u` undoes three changes.

One key, one command or one gesture of the mouse is one change.

## Return to an earlier state

After an undo, a new change starts a new branch. The old states stay.

1. Press `<Space>fu`. The list of the undo states opens, the newest first, with
   what each state changed.
2. Select a state and press `Enter`. The project returns to that state.

The return is not a change: `<Space>fu` again shows all the states, and you can
go to a newer one.

## See the branches as a tree

1. Type `:ext.load undotree`.
2. Press `<Space>uu`. The window of the undo tree shows each branch, and what
   the selected state changed.
3. Press `j` and `k` to select a state, and `Enter` to go there.

With undotree, `g-` and `g+` step through the states in the order that
you made them, across the branches. `:earlier 5m` returns the project to
five minutes ago.

To keep a state after paw closes, save the project, then type
`:checkpoint before the bridge`. See [undotree](../../extensions/undotree/README.md).

If paw stopped and you lost changes, see [How to recover lost work](recover-lost-work.md).

## See also

- [Project files](../reference/project-files.md): saves and safety copies.
