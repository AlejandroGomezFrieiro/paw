# How to find a command or a key you forgot

<!-- tags: find-a-key -->

You can find a key or a command by what it does, with lists that filter
while you type. In each list, `Enter` runs or opens the line that you
select.

## Find a key of this view

1. Press `?`, and the list shows each key of the view that has the
   keyboard, with what it does.
2. Type words of what you want, for example `playhead start`. The search
   looks at the full description, including the part that a narrow screen
   cuts off.
3. Select the line and press `Enter`, and paw does what the key does. Or
   press `Esc`, and use the key from now on.

`<Space>fk` shows the same list.

If you stop in the middle of a sequence of keys, paw lists the keys that
can come next. For example, when you press `<Space>` and wait, the leader
keys show at the bottom of the screen.

## Find a command

1. Press `<Space>f:`, and the list shows each command with what it does
   and its key, if it has one.
2. Type a part of the name or of the description, for example
   `metronome`.
3. Select the line and press `Enter`.

On the command line, `Tab` completes the name of a command and its
arguments. For example, type `:tem` and press `Tab`.

## Read about a key or a command

- Type `:help gl`, and the page that describes `gl` opens at its line.
  For a command, type `:help :export`, and for an option, type
  `:help 'grid'`.
- In a list of keys or commands, press `Ctrl-]` to open the help of the
  selected line.
- To find all the lines of help with a word, type `:helpgrep loop`.

The page [Keys, by idea](../reference/keys.md) has all the keys on one
page, so that you can print it and keep it next to the keyboard.

## See also

- [Help](../reference/help.md): `:help`, tags, `:helpgrep`.
- [Pickers](../reference/pickers.md): every list and its keys.
