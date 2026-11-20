<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 7: Visual mode: select, then act

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 7`.*

In this lesson, we select clips and tracks first, and then we delete, copy, mute and transpose them.

Sometimes you want to see the items before you change them. Visual mode changes the order. First, select with the motions that you know. Then press an operator, and it does its action on the selection.

`v` selects a range of time, and `j` `k` extend it across tracks. `V` selects whole tracks. In the piano roll, `<C-v>` selects a rectangle of pitches and time. Each of the three tracks here has four clips of one bar.

## The idea

In visual mode, the motions extend the selection, and `o` goes to its other end. An operator (`d` `y` `c` `>` `<` `gc` `gl`) or a selection key does an action on it. `x` deletes, `p` replaces it with the register, `~` mutes, `J` joins clips, and `<C-a>` `<C-x>` transpose. With a count, `12<C-a>` transposes one octave. `gv` selects the last selection again. `<Esc>` leaves visual mode and does nothing.

## If you know Vim

`v` `V` `<C-v>`, `o`, `gv` and operators on a selection are from Vim. In visual mode, a count before `>` `<` or `<C-a>` is the amount, as in Vim. In the arrange view, `v` with `j` `k` is already a block of time on some tracks. `V` selects whole tracks, as Vim selects whole lines.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. Press `v` to start a selection. The status line shows VISUAL. Then press `W` to extend the selection over the first bar.
   - ✓ The first bar of Drums is selected.
2. `j` extends the selection down to the next track. Press `j`.
   - ✓ The first bar of Drums and Bass is selected.
3. Now do an action on the selection: `x` deletes it. Press `x`.
   - ✓ The clips are deleted from the two tracks, and the mode is NORMAL again.
4. Press `u` to undo the delete.
   - ✓ The clips are back.
5. `V` selects whole tracks. Press `V`. Press `j` to select Drums and Bass. Press `y` to yank (copy) them.
   - *Hint:* If the selection is wrong, press `<Esc>` to leave visual mode. Then press `gg` and start again.
   - ✓ The register contains two tracks.
6. `G` goes to the last track, and `p` pastes the tracks below it. Press `G`, then `p`.
   - ✓ The song now has five tracks. The copies of Drums and Bass are at the bottom.
7. Press `u` to remove the copies.
   - ✓ The song has three tracks again.
8. `gv` selects the last selection again: the two tracks. Press `gv`, then `~` to mute them.
   - ✓ Drums and Bass are muted, and their `M` flags are lit. On whole tracks, `~` mutes the tracks. On a range of time, it mutes the clips in the range.
9. Press `gv` and `~` again to unmute them.
   - ✓ `~` mutes and unmutes.
10. Visual mode also works in the piano roll. Press `3G` to go to Keys. Press `<CR>` to open its first clip.
   - ✓ The piano roll shows the A minor chord of `k1`.
11. `v` selects a range of time at all pitches. Press `v`. Then press `12<C-a>` to move all notes that start in the range up one octave.
   - *Hint:* Type 1, 2, then Ctrl and a, while the status line shows VISUAL.
   - ✓ The chord is one octave higher. In visual mode, a count gives the amount.
12. Press `<C-w>p` to return to the arrange view. Press `<Space><Space>` to listen, and `<Space><Space>` to stop.
   - ✓ The first chord sounds one octave higher.

## What we did

We selected with `v`, `V` and motions, then used `x`, `y`, `~` or a count and `<C-a>`. `gv` selected again, also in the piano roll.

Previous: [The same grammar on notes](06-grammar-notes.md) · [All lessons](README.md) · Next: [Yank, paste, registers and macros](08-registers.md)
