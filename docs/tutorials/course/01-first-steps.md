<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 1: First steps: the screen, play and quit

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 1`.*

In this lesson, we play a short song, change its tempo and quit paw.

You use paw from the keyboard. Each part of the screen is a view. The arrange view in the middle has one row for each track, and time goes to the right. The status line at the bottom shows the current mode (`NORMAL` now). Below it, you type commands and paw shows messages.

The panel at the bottom is the tutor. It tells you what to do, and it sees when you do it.

The keys have the names that Vim gives them. `j` is the j key and `J` is Shift and j. `<C-r>` is Ctrl and r. `<CR>` is Enter, `<Esc>` is Escape, `<Space>` is the space bar and `<BS>` is Backspace. `gs` is g, then s.

## The idea

You do not need the mouse. Some keys do an action immediately: `x` deletes. Other keys start an action that more keys complete. `:` starts a command line. `g` starts commands of two keys, for example `gs`. `<Space>` starts the keys that work in every view: `<Space><Space>` plays.

If you do not know the current state, press `<Esc>` to return to normal mode. `?` shows the keys of the current view.

## If you know Vim

`:q`, `ZZ` and `ZQ` do the same as in Vim, and `:w` saves. `:` accepts commands by name (`:tempo 120`). It also accepts Ex commands over bars and tracks (`:5,8d`, `:%s/c4/d4/g`). Lesson 17 shows them.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. This short song has three tracks: Drums, Bass and Keys. Press `<Space><Space>` to play it.
   - *Hint:* `<Space>` is the space bar. Look at the ▶ in the status line and at the playhead, which moves across the clips.
   - ✓ The song plays again and again, because the loop is on. The status line shows `loop`.
2. Press `<Space><Space>` again to stop.
   - ✓ The song stops. The playhead stays where it stopped.
3. `gs` moves the playhead to the start. Press `g`, then `s`.
   - *Hint:* Press the two keys one after the other, not together.
   - ✓ The playhead is at the start. The clock in the status line shows 1.1.00 (bar 1, beat 1).
4. The highlighted track header is the cursor. `j` moves it down one track and `k` moves it up. Press `j` two times to go to Keys.
   - *Hint:* If the cursor is below Keys, press `k` to move it up.
   - ✓ The cursor is on Keys.
5. `?` shows each key of the current view. Press `?`. Type `mute` to make the list shorter. Then press `<Esc>` to close it.
   - *Hint:* The text that you type makes the list shorter. `<Esc>` closes the list.
   - ✓ Use this list when you forget a key. `<CR>` (Enter) on a line does the action of its key.
6. `:` opens the command line at the bottom. Type `:tempo 130` and press `<CR>` (Enter). The song becomes faster.
   - *Hint:* Type the colon too. `<Esc>` cancels a command line. `<BS>` on an empty command line closes it.
   - ✓ The tempo is 130 beats per minute. The status line shows it.
7. Press `<Space><Space>` to hear the faster song. Then press `<Space><Space>` to stop it.
   - ✓ The song is faster.
8. To quit paw, type `:q` and `<CR>`. `ZQ` also quits, and `ZZ` saves before it quits. Quit now. The tutor keeps your place, and `:tutor` starts lesson 2 next time.
   - *Hint:* If you do not want to quit now, press `<Space>hn` to start lesson 2.
   - ✓ paw quits.

## What we did

We played a song, moved the cursor, used the command line and found the list of all the keys.

[All lessons](README.md) · Next: [Move the cursor, and keys that change meaning](02-moving.md)
