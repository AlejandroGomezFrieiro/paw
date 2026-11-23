<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 1: First steps: the screen, play and quit

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 1`.*

In this lesson, we play a short song, change its tempo and quit paw.

You use paw from the keyboard, and each part of the screen is a view. The arrange view in the middle has one row for each part, and time goes to the right. The status line at the bottom shows the current mode, which is `NORMAL` now. Below the status line, you type commands and paw shows messages.

The panel at the bottom is the tutor, which tells you what to do and checks each step when you do it.

The keys have the names that Vim gives them. For example, `j` is the j key, `J` is Shift and j, and `<C-r>` is Ctrl and r. Moreover, `<CR>` is Enter, `<Esc>` is Escape, `<Space>` is the space bar and `<BS>` is Backspace, and `gs` means g and then s.

## The idea

You do not need the mouse in paw. Some keys do an action immediately, e.g., `x` deletes. Other keys start an action that more keys complete. For example, `:` starts a command line, and `g` starts commands of two keys, such as `gs`. Moreover, `<Space>` starts the keys that work in every view, such as `<Space><Space>`, which plays.

If you do not know which mode you are in, press `<Esc>` to return to normal mode. To see the keys of the current view, press `?`.

## If you know Vim

`:q`, `ZZ` and `ZQ` do the same as in Vim, and `:w` saves. The command line accepts commands by name, e.g., `:tempo 120`. It also accepts Ex commands over bars and parts, e.g., `:5,8d` and `:%s/c4/d4/g`, and lesson 17 shows how to use them.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. The song has three parts, which are Drums, Bass and Keys. Press `<Space><Space>` to play it.
   - *Hint:* `<Space>` is the space bar. Look at the ▶ in the status line and at the playhead, which moves across the clips.
   - ✓ The song plays again and again, because the loop is on. The status line shows `loop`.
2. Press `<Space><Space>` again to stop.
   - ✓ The song stops. The playhead stays where it stopped.
3. `gs` moves the playhead to the start. Press `g`, then `s`.
   - *Hint:* Press the two keys one after the other, not together.
   - ✓ The playhead is at the start. The clock in the status line shows 1.1.00 (bar 1, beat 1).
4. The highlighted part header is the cursor. `j` moves it down one part and `k` moves it up. Press `j` two times to go to Keys.
   - *Hint:* If the cursor is below Keys, press `k` to move it up.
   - ✓ The cursor is on Keys.
5. `?` shows each key of the current view. Press `?`, and type `mute` to make the list shorter. Then press `<Esc>` to close the list.
   - *Hint:* The text that you type makes the list shorter. `<Esc>` closes the list.
   - ✓ When you forget a key, you can find it in the list. `<CR>` (Enter) on a line does the action of its key.
6. `:` opens the command line at the bottom. Type `:tempo 130` and press `<CR>` (Enter). The song becomes faster.
   - *Hint:* Type the colon too. `<Esc>` cancels a command line. `<BS>` on an empty command line closes it.
   - ✓ The tempo is 130 beats per minute. The status line shows it.
7. Press `<Space><Space>` to hear the faster song. Then press `<Space><Space>` to stop it.
   - ✓ The song plays faster now.
8. To quit paw, type `:q` and `<CR>`. `ZQ` also quits, and `ZZ` saves before it quits. Quit now. The tutor keeps your place, so `:tutor` starts lesson 2 the next time.
   - *Hint:* If you do not want to quit now, press `<Space>hn` to start lesson 2.
   - ✓ paw quits.

## What we did

We played a song, moved the cursor, used the command line and found the list of all the keys.

- Next: [Move the cursor, and keys that change meaning](02-moving.md)
- [All lessons](README.md)
