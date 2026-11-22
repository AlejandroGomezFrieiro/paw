# How to undo, and return to an earlier state

<!-- tags: undo-guide -->

You can undo a change, and you can return to any earlier state of the
project. paw keeps every state, including the states that you undid and
then changed.

## Undo and redo

- Press `u` to undo the last change. The message says what it undid, for
  example `undid Move clips later`.
- Press `<C-r>` to redo it.
- A count undoes more, so `3u` undoes three changes.

One key, one command or one gesture of the mouse is one change.

## Return to an earlier state

After an undo, a new change starts a new branch, and the old states stay.

1. Press `<Space>fu`. The list of the undo states opens, the newest first,
   with what each state changed.
2. Select a state and press `Enter`, and the project returns to that
   state.

The return is not a change, so `<Space>fu` again shows all the states, and
you can go to a newer one.

## See the branches as a tree

1. Type `:ext.load undotree`.
2. Press `<Space>pu`. The window of the undo tree shows each branch, and
   what the selected state changed.
3. Press `j` and `k` to select a state, and `Enter` to go there.

With undotree, `g-` and `g+` step through the states in the order that
you made them, across the branches. `:earlier 5m` returns the project to
five minutes ago.

## Undo after you open the project again

When you save a project folder with `:w`, paw keeps its undo history in the
undo file. Close paw, open the project again, and press `u`. paw undoes the
changes that you made before the save, and `<Space>fu` lists the states and
branches of the earlier sessions.

- If the message says `the undo file is for another version of the
  project: not read`, the files of the project changed outside paw after
  the save, for example with `git checkout`. The undo history starts at
  the project as it opened.
- To keep no undo file, put `paw.opt.undofile = false` in your
  configuration. The details are in [Files that paw keeps](../reference/state-files.md#the-undo-file).

If you want to keep a state as a file of its own, save the project, and then
type `:checkpoint before the bridge`. The details are in
[undotree](../../extensions/undotree/README.md).

If paw stopped and you lost changes, see [How to recover lost work](recover-lost-work.md).

## See also

- [Project files](../reference/project-files.md): saves and safety copies.
