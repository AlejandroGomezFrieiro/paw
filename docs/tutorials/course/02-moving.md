<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 2: Move the cursor, and keys that change meaning

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 2`.*

In this lesson, we move the cursor through a song by steps, clips, bars and tracks. Then we use the same keys in a different mode and in a different view.

In the arrange view, each track is a row, and time goes from left to right along it. One grid step is one beat. The keys that move the cursor are called motions, and a number before a motion repeats it. Some motions move by small steps or by bars, others move to clips or to the ends of clips, and others move to other tracks.

A key can have a different meaning in a different mode, e.g., normal, visual or insert mode. It can also have a different meaning in a different view, e.g., the arrange view, the piano roll or the mixer. The status line always shows the current mode, and the view that gets the keys has a brighter frame or highlight.

## The idea

`h` and `l` move one grid step. `w`, `b` and `e` move by clips, to the start of the next clip, the start of the current clip and the end of the current clip. `W` and `B` move by bars.

`0` goes to the start of the project, and `^` goes to the first clip. `$` goes to the end of the last clip. `j` and `k` move by tracks, and `gg` and `G` go to the first and the last track. `5|` goes to bar 5. You type a count before the motion, e.g., `4l`, `2W` or `3j`.

NORMAL mode is for moving and for actions, VISUAL mode (`v`) is for selecting, and INSERT mode (`i`) is for adding notes. PENDING shows while an operator waits for its motion, and `<Esc>` returns to NORMAL.

## If you know Vim

`hjkl`, `w` `b` `e`, `W` `B`, `0` `^` `$`, `gg` `G`, counts and `|` are all in paw, with a few differences from Vim. `w` goes to the starts of clips, and there is no WORD, so `W` and `B` move by bars instead. `0` is the start of the project and `^` is the first clip. `|` and `:5` take a bar number, not a column or a line.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. The cursor is at the start of the Bass track. `l` moves it right one grid step (one beat), and `h` moves it left. Press `l` three times.
   - ✓ The cursor moved three beats. The clock at the top left of the arrange view shows 1.4.00, bar 1 beat 4.
2. A number before a motion repeats the motion. Press `4l` to move four beats.
   - *Hint:* Type the 4 and then the l. If the cursor is at a different beat, press `0` and then `3l`.
   - ✓ The cursor is on beat 7, near the end of the clip `verse`.
3. `0` moves the cursor to the start of the project. Press `0`.
   - ✓ The cursor is at the start.
4. `w` moves to the start of the next clip on the track. Press `w`.
   - ✓ The cursor is on `chorus`, which starts at beat 12 (bar 4).
5. `e` moves to the end of the clip, and `b` moves to its start. Press `e`, then `b`.
   - ✓ `w`, `b` and `e` move to the start of the next clip, the start of the current clip and the end of the current clip.
6. `W` and `B` move by bars (four beats here). Press `2W` to move two bars.
   - ✓ The cursor is on bar 6 (beat 20).
7. `$` moves to the end of the last clip of the track, and `^` moves to its first clip. Press `$`.
   - ✓ The cursor is at the end of `outro`, where the song ends.
8. `G` moves to the last track, and `gg` moves to the first track. Press `G`.
   - ✓ The cursor is on Pad, the last track. `3G` moves to track 3.
9. `5|` moves to bar 5. `:5` and `<CR>` do the same. Press `5|`.
   - *Hint:* `|` is the bar key. On many keyboards, it is Shift and backslash.
   - ✓ The cursor is on bar 5, where the pad starts.
10. Now we use the same keys in a different mode. Press `v`, and the status line shows VISUAL. In visual mode, each motion makes the selection larger. Press `l` two times.
    - ✓ In visual mode, `l` moves the cursor and also selects. Lesson 7 shows what you can do with a selection.
11. `<Esc>` always returns to NORMAL. Press `<Esc>`.
    - ✓ The mode is NORMAL again.
12. Now we use a different view. `<CR>` (Enter) on a clip opens it in the piano roll. Press `<CR>` on the pad clip.
    - *Hint:* The cursor must be on a clip. Press `5|` on the Pad track to move it there.
    - ✓ The piano roll now gets the keys.
13. In the piano roll, the rows are pitches, so `k` moves up one semitone instead of one track. Press `k` two times, and you hear each pitch.
    - ✓ The key is the same as in the arrange view, and it still moves up, but in the piano roll it moves by pitch.
14. `<Esc>` does not leave the current window in any view, and `<C-w>p` returns to the previous window. Press `<C-w>p`. Then press `gp` to move the playhead to the cursor. Press `<Space><Space>` to play and `<Space><Space>` to stop.
    - *Hint:* `<Space><Space>` alone plays from the cursor. `gp` puts the playhead there first, and `<S-CR>` plays from the playhead.
    - ✓ The song played from bar 5, where the melody starts.

## What we did

We moved by steps, clips, bars and tracks, with counts. The same keys had other meanings in visual mode and in the piano roll.

- Previous: [First steps: the screen, play and quit](01-first-steps.md)
- Next: [Tracks, clips and notes](03-making.md)
- [All lessons](README.md)
