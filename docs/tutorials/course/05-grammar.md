<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 5: The grammar: operators, motions, text objects

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 5`.*

In this lesson, we delete, mute and loop clips with short commands, and we repeat the commands with `.`.

Most edits in paw use the same grammar. You type an operator, which is the action, and then a motion or a text object, which is the item. For example, `d` is delete and `w` is "to the next clip", so `dw` deletes up to the next clip. `ic` is "the clip under the cursor", so `dic` deletes the clip under the cursor.

A count gives the quantity, e.g., `d2W` deletes two bars. When you type the operator two times, as in `dd`, it acts on whole parts. `.` repeats the last change at the cursor.

In the practice project, the Beat part has four clips, which are kick, snare, fill and crash, and the Bass part plays below them.

## The idea

The operators that edit are `d` (delete), `y` (yank, which copies) and `c` (change). Other operators move and mark clips, e.g., `>` and `<` move later and earlier, and `=` snaps to the grid. `gc` mutes, and `gl` loops. The motions are all the keys from lesson 2.

The text objects are `ic` (the clip) and `ac` (the clip with the gap after it). Moreover, `ib` is the bar, `il` the loop, `it` the whole part and `ie` the project. When you learn some operators, motions and text objects, you can use every combination of them, so six operators and ten motions give sixty commands.

## If you know Vim

paw uses the grammar of Vim with no change, which is an operator, a count, and a motion or a text object. The operator typed two times selects whole lines, and in paw the lines are parts. `.` accepts a new count.

In Vim, `gc` changes lines to comments, and in paw it mutes. `gl` (loop) is new. `c` makes the range empty and opens a new clip in insert mode.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. The cursor is at the start of `kick`. `d` is the delete operator and `w` is the motion to the next clip. Press `dw`.
   - *Hint:* After `d`, the status line shows PENDING, which means that the operator waits for its motion. `<Esc>` cancels the operator.
   - ✓ paw deleted `kick`, because `dw` deletes from the cursor to the start of `snare`.
2. Press `u` to bring `kick` back.
   - ✓ The part has its four clips again.
3. A text object names an item instead of a movement, e.g., `ic` is the clip under the cursor. Press `w` to go to `snare`, then press `dic`.
   - ✓ `dic` means "delete in clip", and there is now a gap where `snare` was.
4. `.` repeats the last change. Press `w` to go to `fill`, and then press `.` to delete it too.
   - ✓ `.` did `dic` again, on the clip that is under the cursor now.
5. To undo the two changes, press `u` two times.
   - ✓ The part has four clips again.
6. A count goes with the motion, so `d2W` deletes two bars from the cursor. Press `0`, then `d2W`.
   - ✓ paw deleted two bars of Beat. Bass did not change, because the operator works on the part of the cursor.
7. Press `u` to undo that change.
   - ✓ The two bars are back.
8. Other operators accept the same motions and objects, e.g., `gc` mutes. Press `gcic` to mute `kick`.
   - ✓ `kick` is muted and shows in gray. To unmute it, press `gcic` again.
9. Press `w` to go to `snare`. Press `.` to mute it in the same way.
   - ✓ `.` repeats each type of change, e.g., delete, mute and move.
10. An operator typed two times selects whole parts, so `dd` deletes a part. Press `j` to go to Bass, then press `dd`.
    - ✓ paw deleted the Bass part and keeps it in the register.
11. `p` puts the deleted item after the cursor, and a part goes below the cursor. Press `p`.
    - ✓ Bass is back, with its synth and its clip, so a delete is also a cut.
12. `gl` is the loop operator. Press `k` to go up to Beat, and press `0` and `w` to put the cursor on `snare`. Then press `glic`.
    - ✓ The loop is now over the snare clip, and the ruler shows the loop.
13. Press `gcic` to unmute `snare`. Press `<Space><Space>` to hear the loop, and `<Space><Space>` again to stop.
    - ✓ The snare bar and the bass play again and again.

## What we did

We used operators with motions (`dw`, `d2W`) and with text objects (`dic`, `gcic`, `glic`), `dd` for parts, and `.` to repeat.

- Previous: [The piano roll and insert mode](04-pianoroll.md)
- Next: [The same grammar on notes](06-grammar-notes.md)
- [All lessons](README.md)
