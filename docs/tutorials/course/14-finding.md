<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 14: Find a command or a key

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 14`.*

In this lesson, we find keys and commands from a part of their name, and then we use them.

You do not need to remember all the keys, because paw shows what you can do at each point. When you stop in the middle of a key sequence, paw shows the keys that can come next, and `?` shows all the keys of the current view. `:` runs a command by its name, and Tab completes the name. Pickers find a command, a key, a track or a clip from some letters of its name.

Each key runs a command with a name, so you can type the name of each action that a key does. You can also map each command that you find to a key.

## The idea

Key hints show when you stop after the start of a sequence, e.g., `g`, `<Space>`, `d` or `"`. `?` is the list of keys for the view that has the keys, and `:commands` shows each command and what it does.

The keys that start with `<Space>f` open pickers. `<Space>f:` finds a command and `<Space>fk` a key, while `<Space>ft` finds a track and `<Space>fc` a clip. Moreover, `<Space>fm` finds a marker and `<Space>fr` a region, while `<Space>f"` finds a register and `<Space>fp` a picker.

In a picker, the text that you type makes the list shorter. The letters must be in order, but they can have other letters between them. `<C-n>` and `<C-p>` move, `<CR>` selects and `<Esc>` cancels. `K` gives data about the clip and the track under the cursor.

## If you know Vim

The key hints are built into paw. The pickers use fuzzy matching, and `<C-n>` `<C-p>` move in them. `:` completes with Tab and keeps a history, which `<Up>` shows.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. Press `g` and wait. After half a second, a box shows all the keys that can come after `g`, and then you can press `<Esc>` to close the box.
   - *Hint:* Do not press a key until the box shows.
   - ✓ Each key sequence that is not complete shows what can come next. Later, try `<Space>`, `d` or `"`.
2. `:commands` shows each command and what it does. Type `:commands` and `<CR>`, look at the list, and then press `q` to close it.
   - ✓ Each key that you used runs one of the commands in the list.
3. Tab completes the names of commands. Press `j` to go to Bass. Type `:track.vol` and press `<Tab>`, and the name becomes `track.volume`. Then press `<Space>`, type `-6` and press `<CR>`.
   - ✓ Bass is at -6 dB, and `+` and `-` run the same command, `track.volume`.
4. `<Space>f:` opens a picker of all the commands. When you type some letters, `<CR>` runs the first command in the list. Press `<Space>f:`, type `metro` and press `<CR>`.
   - ✓ The metronome is on. You ran `transport.metronome` without knowing its name or its key.
5. `<Space>fk` finds a key from its action. Press `<Space>fk` and type `loop` to see all the keys for the loop, and then press `<Esc>`.
   - ✓ The list showed `gL`, `gl` and `il`, and `<CR>` on a line types its key for you.
6. `<Space>ft` goes to a track by its name. Press `<Space>ft`, type `dr` and press `<CR>`.
   - ✓ The cursor is on Drums, and `<Space>fc` does the same for clips.
7. `K` gives data about the item under the cursor, which is the clip, the track and its devices. Press `K`, and then `q` to close the window.
   - ✓ With `K`, you can see the devices, sends and automation of a track with one key.
8. Listen with the click. Press `<Space><Space>`, and then `<Space><Space>` to stop and `gm` to disable the click.
   - ✓ The bass is quieter, and the click came from a command that you found by its name.

## What we did

We used key hints, `?`, `:commands`, Tab on the command line, the `<Space>f` pickers and `K`.

- Previous: [Save and export](13-saving.md)
- Next: [Make paw your own: options, keys, commands](15-your-own.md)
- [All lessons](README.md)
