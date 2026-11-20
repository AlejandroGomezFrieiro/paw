<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 14: Find a command or a key

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 14`.*

In this lesson, we find keys and commands from a part of their name. Then we use them.

Nobody remembers all the keys. paw shows what you can do at each point. Stop in the middle of a key sequence, and paw shows the keys that can come next. `?` shows all the keys of the current view. `:` runs a command by its name, and Tab completes the name. Pickers find a command, a key, a track or a clip from some letters of its name.

Each key runs a command with a name. So you can type the name of each action that a key does. You can also map each command that you find to a key.

## The idea

Key hints show when you stop after the start of a sequence (`g`, `<Space>`, `d`, `"`). `?` is the list of keys for the view that has the keys. `:commands` shows each command and what it does.

`<Space>fc` finds a command, `<Space>fk` a key, `<Space>ft` a track and `<Space>fl` a clip. `<Space>fa` finds a device, `<Space>fm` a mark, `<Space>fr` a register and `<Space>fp` a picker. In a picker, the text that you type makes the list shorter. The letters must be in order, but they can have other letters between them. `<C-n>` `<C-p>` move, `<CR>` selects and `<Esc>` cancels. `K` gives data about the clip and the track under the cursor.

## If you know Vim

The hints are those of which-key, built into paw. The pickers work as in Telescope: fuzzy, with `<C-n>` `<C-p>`. `:` completes with Tab and keeps a history (`<Up>`).

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. Press `g` and wait. After half a second, a box shows all the keys that can come after `g`. Then press `<Esc>` to close the box.
   - *Hint:* Do not press a key until the box shows.
   - ✓ Each command that is not complete shows what can come next. Try `,`, `d` or `"` later.
2. `:commands` shows each command and what it does. Type `:commands` and `<CR>`. Look at the list, then press `q` to close it.
   - ✓ Each key that you used runs one of those commands.
3. Tab completes the names of commands. Press `j` to go to Bass. Type `:track.vol` and press `<Tab>`: it becomes `track.volume`. Then press `<Space>`, type `-6` and press `<CR>`.
   - ✓ Bass is at -6 dB. `+` and `-` run the command `track.volume`.
4. `<Space>fc` opens a picker of all the commands. Type some letters, and `<CR>` runs the first command. Press `<Space>fc`, type `metro` and press `<CR>`.
   - ✓ The metronome is on. You ran `transport.metronome`, but you did not know its name or its key.
5. `<Space>fk` finds a key from its action. Press `<Space>fk` and type `loop` to see all the keys for the loop. Then press `<Esc>`.
   - ✓ The list showed `gL`, `gl` and `il`. `<CR>` on a line types its key for you.
6. `<Space>ft` goes to a track by its name. Press `<Space>ft`, type `dr` and press `<CR>`.
   - ✓ The cursor is on Drums. `<Space>fl` does the same for clips.
7. `K` gives data about the item under the cursor: the clip, the track and its devices. Press `K`, then `q` to close it.
   - ✓ `K` is the fastest way to see the devices, sends and automation of a track.
8. Listen with the click. Press `<Space><Space>`, then `<Space><Space>` to stop and `gm` to disable the click.
   - ✓ The bass is quieter, and the click came from a command that you found by its name.

## What we did

We used key hints, `?`, `:commands`, Tab on the command line, the `<Space>f` pickers and `K`.

Previous: [Save and render](13-saving.md) · [All lessons](README.md) · Next: [Make paw your own: options, keys, commands](15-your-own.md)
