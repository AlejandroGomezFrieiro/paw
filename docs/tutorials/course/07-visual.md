<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 7: Visual mode: select, then act

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 7`.*

In this lesson, we select clips and tracks first, and then we delete, copy, mute and transpose them.

Visual mode lets you see the items before you change them, because it changes the order of the keys. First, you select with the motions that you know. Second, you press an operator, and it does its action on the selection.

`v` selects a range of time, and `j` and `k` extend it across tracks. `V` selects whole tracks. In the piano roll, `<C-v>` selects a rectangle of pitches and time. In the practice project, each of the three tracks has four clips of one bar.

## The idea

In visual mode, the motions extend the selection, and `o` goes to its other end. An operator (`d` `y` `c` `>` `<` `gc` `gl`) or a selection key does an action on the selection. For example, `x` deletes, `p` replaces the selection with the register, and `~` mutes. Moreover, `J` joins clips, and `<C-a>` and `<C-x>` transpose, so with a count, `12<C-a>` transposes one octave.

`gv` selects the last selection again, and `<Esc>` leaves visual mode and does nothing.

## If you know Vim

`v` `V` `<C-v>`, `o`, `gv` and operators on a selection come from Vim. In visual mode, a count before `>` `<` or `<C-a>` is the amount, as in Vim. In the arrange view, `v` with `j` and `k` already selects a block of time on some tracks, and `V` selects whole tracks, as Vim selects whole lines.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. Press `v` to start a selection, and the status line shows VISUAL. Then press `W` to extend the selection over the first bar.
   - ✓ The first bar of Drums is selected.
2. `j` extends the selection down to the next track. Press `j`.
   - ✓ The first bar of Drums and Bass is selected.
3. Now do an action on the selection. `x` deletes the selection, so press `x`.
   - ✓ paw deleted the clips from the two tracks, and the mode is NORMAL again.
4. Press `u` to undo the delete.
   - ✓ The clips are back.
5. `V` selects whole tracks. Press `V`, and press `j` to select Drums and Bass. Then press `y` to yank (copy) them.
   - *Hint:* If the selection is wrong, press `<Esc>` to leave visual mode, and then press `gg` and start again.
   - ✓ The register contains two tracks.
6. `G` goes to the last track, and `p` pastes the tracks below it. Press `G`, then `p`.
   - ✓ The song now has five tracks, with the copies of Drums and Bass at the bottom.
7. Press `u` to remove the copies.
   - ✓ The song has three tracks again.
8. `gv` selects the last selection again, which is the two tracks. Press `gv`, then `~` to mute them.
   - ✓ Drums and Bass are muted, and their `M` flags are lit. On whole tracks, `~` mutes the tracks, and on a range of time, it mutes the clips in the range.
9. Press `gv` and `~` again to unmute them.
   - ✓ `~` mutes and unmutes.
10. Visual mode also works in the piano roll. Press `3G` to go to Keys, and press `<CR>` to open its first clip.
    - ✓ The piano roll shows the A minor chord of `k1`.
11. `v` selects a range of time at all pitches. Press `v`, and then press `12<C-a>` to move all notes that start in the range up one octave.
    - *Hint:* While the status line shows VISUAL, type 1, 2, and then Ctrl and a.
    - ✓ The chord is one octave higher, because in visual mode a count gives the amount.
12. Press `<C-w>p` to return to the arrange view. Press `<Space><Space>` to listen, and `<Space><Space>` to stop.
    - ✓ The first chord sounds one octave higher.

## What we did

We selected with `v`, `V` and motions, and then used `x`, `y`, `~`, or a count and `<C-a>`. We also used `gv` to select again, and we used visual mode in the piano roll.

- Previous: [The same grammar on notes](06-grammar-notes.md)
- Next: [Yank, paste, registers and macros](08-registers.md)
- [All lessons](README.md)
