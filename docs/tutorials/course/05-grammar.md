<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 5: The grammar: operators, motions, text objects

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 5`.*

In this lesson, we delete, mute and loop clips with short commands. Then we repeat them with `.`.

This grammar is the center of paw. Most edits are a short sentence: an operator (the action), then a motion or a text object (the item). `d` is delete and `w` is "to the next clip", so `dw` deletes up to the next clip. `ic` is "the clip under the cursor", so `dic` deletes this clip.

A count gives the quantity: `d2W` deletes two bars. The operator two times selects whole tracks: `dd`. `.` repeats the last change at the cursor.

In this practice project, the Beat track has four clips: kick, snare, fill and crash. Bass plays below them.

## The idea

The operators are `d` delete, `y` yank (copy) and `c` change. `>` `<` move later and earlier, `=` snaps to the grid, `gc` mutes and `gl` loops. The motions are all the keys from lesson 2.

The text objects are `ic` the clip and `ac` the clip with the gap after it. `ib` is the bar, `il` the loop, `it` all of the track and `ie` the project. Learn some of each, and you know all their combinations. Six operators and ten motions make sixty commands.

## If you know Vim

This is the grammar of Vim, with no change: an operator, a count, and a motion or a text object. The operator two times selects whole lines, which are tracks here. `.` accepts a new count.

In Vim, `gc` changes lines to comments. Here it mutes. `gl` (loop) is new. `c` makes the range empty and opens a new clip in insert mode.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. The cursor is at the start of `kick`. `d` is the delete operator and `w` is the motion to the next clip. Press `dw`.
   - *Hint:* After `d`, the status line shows PENDING: the operator waits for its motion. `<Esc>` cancels it.
   - ✓ `kick` is deleted. `dw` deleted from the cursor to the start of `snare`.
2. Press `u` to bring it back.
   - ✓ The track has its four clips again.
3. A text object names an item, not a movement. `ic` is the clip under the cursor. Press `w` to go to `snare`, then press `dic`.
   - ✓ `dic` means "delete in clip". A gap is now where `snare` was.
4. `.` repeats the last change. Press `w` to go to `fill`. Then press `.` to delete it too.
   - ✓ `.` did `dic` again, on the clip that is under the cursor now.
5. Undo the two changes: press `u` two times.
   - ✓ The track has four clips again.
6. A count goes with the motion: `d2W` deletes two bars from the cursor. Press `0`, then `d2W`.
   - ✓ Two bars of Beat are deleted. Bass did not change, because the operator works on the track of the cursor.
7. Press `u` to undo that change.
   - ✓ The two bars are back.
8. Other operators accept the same motions and objects. `gc` mutes. Press `gcic` to mute `kick`.
   - ✓ `kick` is muted and gray. `gcic` again unmutes it.
9. Press `w` to go to `snare`. Press `.` to mute it in the same way.
   - ✓ `.` repeats each type of change: delete, mute and move.
10. An operator two times selects whole tracks: `dd` deletes a track. Press `j` to go to Bass, then press `dd`.
   - ✓ The Bass track is deleted, and paw keeps it in the register.
11. `p` puts the deleted item after the cursor. A track goes below the cursor. Press `p`.
   - ✓ Bass is back, with its synth and its clip. So a delete is also a cut.
12. `gl` is the loop operator. Press `k` to go up to Beat. Press `0` and `w` to put the cursor on `snare`. Then press `glic`.
   - ✓ The loop is the snare clip. The ruler shows it.
13. Press `gcic` to unmute `snare`. Press `<Space><Space>` to hear the loop. `<Space><Space>` stops.
   - ✓ The snare bar and the bass play again and again.

## What we did

We used operators with motions (`dw`, `d2W`) and with text objects (`dic`, `gcic`, `glic`), `dd` for tracks, and `.` to repeat.

Previous: [The piano roll and insert mode](04-pianoroll.md) · [All lessons](README.md) · Next: [The same grammar on notes](06-grammar-notes.md)
