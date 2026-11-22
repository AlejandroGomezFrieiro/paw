<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 17: Ranges, :s and :g: edit by line

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 17`.*

In this lesson, we change bars, tracks and notes of a song from the command line.

Operators and visual mode do their action at the cursor, but the command line can do an action at many places at the same time. A range before a command gives the places as bars and tracks. For example, `:2,3d` makes bars 2 and 3 empty, and `:t2 4d` makes only bar 4 of track 2 empty. `:%s/c4/d4/g` changes each C4 of the song to a D4.

In the practice project, each of the three tracks has four clips of one bar. While you type, look at the right end of the command line, which shows what the line will do. The views also highlight the items before paw changes them.

## The idea

A range can be of time, e.g., `5,8` is bars and `5.3` is a beat. `%` is all, `.` is the bar of the cursor, and `$` is the last bar. Moreover, `'a,'b` is marks, `'<,'>` is the selection, and `.+4` is an offset. A range can also be of tracks (`t2,t4`, `t*`, `t/Drums/`), or of both (`:t2 5,8d`).

The commands are `d` `y` `co` `m` `>` `<` `j`, `mute` `solo` `volume` `pan`, `transpose` `quantize`, `normal`, `s` and `g`. A pattern selects notes or clips by their fields, e.g., `c4`, `vel>100`, `len<1/8` or `name:Verse`. Each line is one undo step.

## If you know Vim

Ranges, `:d` `:y` `:co` `:m` `:>` `:j` and `:normal` come from Vim, and so do `:s` with `g`, `c` and `n`, `:&`, `:g` and `:v`. A bar takes the place of a line, and `inccommand` comes from Neovim.

Without `g`, only the first match in each bar changes, as only the first match on each line changes in Vim. paw does not have the `:t` of Vim, because `t` starts a range of tracks.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. Type `:2,3d` (bars 2 to 3, delete). Before you press Enter, look at the right end of the line, which shows `bars 2–3`, and at the ruler, which shades the bars. Then press `<CR>`.
   - ✓ Bars 2 and 3 are empty on all tracks, and the register contains the deleted clips.
2. The whole command line is one change, so one `u` undoes it. Press `u`.
   - ✓ The bars are back after one undo step.
3. The tracks come first in a range, so `:t2 4d` makes only bar 4 of track 2, Bass, empty. Type it and press `<CR>`.
   - ✓ Only Bass lost its last bar.
4. Press `u` again.
   - ✓ The bar is back.
5. `t*` is all the tracks. To make them all 3 dB quieter, type `:t* volume -=3`, and then press `<CR>`.
   - ✓ Each fader went down by 3 dB, and `:t* volume -6` would set them all to -6 dB.
6. Now we use `:s`. Type `:%s/c4/d4/g`, and the line counts the C4 notes of the song while the clips that contain them are highlighted. Press `<CR>`.
   - *Hint:* `<Esc>` leaves the line and changes nothing, so you can type `:` and the command again.
   - ✓ Each C4 is now a D4, because `%` was the whole song, and `g` was each match in each bar.
7. `:g` runs a command on each match. To mute the Bass clips by their name, type `:g/name:b/mute`, and then press `<CR>`.
   - ✓ The four Bass clips are muted. `:g/vel>100/` with no command puts the matches in the quickfix list, where `]q` goes to the next match.

## What we did

We used `:2,3d`, `:t2 4d`, `:t* volume -=3`, `:%s/c4/d4/g` and `:g/name:b/mute`, which are each a range followed by a command, with one undo step for each.

- Previous: [The bundled extensions](16-extensions.md)
- [All lessons](README.md)
