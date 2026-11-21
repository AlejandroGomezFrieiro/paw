# How to find a command or a key you forgot

<!-- tags: find-a-key -->

This guide shows you how to find a key or a command by what it does. Each list below filters while you type. `Enter`
runs or opens the line that you select.

## Find a key of this view

1. Press `?`. The list shows each key of the view that has the keyboard,
   with what it does.
2. Type words of what you want, for example `playhead start`. The search looks
   at the full description, also at the part that a narrow screen cuts.
3. Select the line and press `Enter`. paw does what the key does.
   Or press `Esc`, and use the key from now on.

`<Space>fk` shows the same list.

If you stop in the middle of a sequence of keys, paw lists the keys that
can come next. For example, press `<Space>` and wait: the leader keys show at the
bottom of the screen.

## Find a command

1. Press `<Space>f:`. The list shows each command with its key, if it has one,
   and what it does.
2. Type a part of the name or of the description, for example
   `metronome`.
3. Select the line and press `Enter`.

On the command line, `Tab` completes the name of a command and its
arguments: type `:tem` and press `Tab`.

## Read about a key or a command

- Type `:help gl`. The page that describes `gl` opens at its line.
- For a command, type `:help :render`. For an option, type
  `:help 'grid'`.
- In a list of keys or commands, press `Ctrl-]` to open the help of the
  selected line.
- To find all the lines of help with a word, type `:helpgrep loop`.

The page [Keys, by idea](../reference/keys.md) has all the keys on one page,
to print and keep next to the keyboard.

## See also

- [Help](../reference/help.md): `:help`, tags, `:helpgrep`.
- [Pickers](../reference/pickers.md): every list and its keys.
