<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 2: Move the cursor, and keys that change meaning

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 2`.*

In this lesson, we move the cursor through a song by steps, clips, bars and tracks. Then we use the same keys in a different mode and in a different view.

In the arrange view, a track is a line and time goes along it. One beat is one grid step. A clip on a track is like a word on a line. The keys that move the cursor are motions. The motions go in groups: small steps, clips, bars, the ends of items, and other tracks. A number before a motion repeats it.

A key can have a different meaning in a different mode (normal, visual, insert). It can also have a different meaning in a different view (the arrange view, the piano roll, the mixer). The status line always shows the current mode. The view that gets the keys has a brighter frame or highlight.

## The idea

`h` and `l` move one grid step. `w`, `b` and `e` move by clips: the next start, this start and this end. `W` and `B` move by bars.

`0` goes to the start of the project, and `^` goes to the first clip. `$` goes to the end of the last clip. `j` and `k` move by tracks. `gg` and `G` go to the first and the last track, and `5|` goes to bar 5. A count comes first: `4l`, `2W`, `3j`.

The modes are NORMAL, to move and to do actions, VISUAL (`v`), to select, and INSERT (`i`), to add notes. PENDING shows while an operator waits for its motion. `<Esc>` returns to NORMAL.

## If you know Vim

`hjkl`, `w` `b` `e`, `W` `B`, `0` `^` `$`, `gg` `G`, counts and `|` are all here. These are the differences. `w` goes to the starts of clips, and there is no WORD. `W` and `B` move by bars. `0` is the start of the project and `^` is the first clip. `|` and `:5` take a bar number, not a column or a line.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. The cursor is at the start of the Bass track. `l` moves it right one grid step (one beat), and `h` moves it left. Press `l` three times.
   - ✓ The cursor moved three beats. The clock at the top left of the arrange view shows 1.4.00, bar 1 beat 4.
2. A number before a motion repeats the motion. Press `4l` to move four beats.
   - *Hint:* Type the 4 and then the l. If the cursor is at a different beat, press `0` and then `3l`.
   - ✓ The cursor is on beat 7, near the end of the clip `verse`.
3. `0` moves the cursor to the start of the project. Press `0`.
   - ✓ The cursor is at the start.
4. A clip is like a word: `w` moves to the start of the next clip on the track. Press `w`.
   - ✓ The cursor is on `chorus`, which starts at beat 12 (bar 4).
5. `e` moves to the end of the clip, and `b` moves to its start. Press `e`, then `b`.
   - ✓ `w` `b` `e` move to the next start, this start and this end.
6. `W` and `B` move by bars (four beats here). Press `2W` to move two bars.
   - ✓ The cursor is on bar 6 (beat 20).
7. `$` moves to the end of the last clip of the track, and `^` moves to its first clip. Press `$`.
   - ✓ The cursor is at the end of `outro`, where the song ends.
8. Tracks are lines: `G` moves to the last track and `gg` to the first. Press `G`.
   - ✓ The cursor is on Pad, the last track. `3G` moves to track 3.
9. `5|` moves to bar 5. `:5` and `<CR>` do the same. Press `5|`.
   - *Hint:* `|` is the bar key. On many keyboards, it is Shift and backslash.
   - ✓ The cursor is on bar 5, where the pad starts.
10. Now we use the same keys in a different mode. Press `v`. The status line shows VISUAL, and each motion makes a selection larger. Press `l` two times.
   - ✓ In visual mode, `l` moves the cursor and also selects. Lesson 7 shows what you can do with a selection.
11. `<Esc>` always returns to NORMAL. Press `<Esc>`.
   - ✓ The mode is NORMAL again.
12. Now we use a different view. `<CR>` (Enter) on a clip opens it in the piano roll. Press `<CR>` on the pad clip.
   - *Hint:* The cursor must be on a clip. Press `5|` on the Pad track to move it there.
   - ✓ The piano roll gets the keys now.
13. Here the rows are pitches, so `k` moves up one semitone, not one track. Press `k` two times. You hear each pitch.
   - ✓ The key is the same, but the view and the meaning are different. It still moves up.
14. `<Esc>` stays in the current window, in each view. `<C-w>p` returns to the previous window. Press `<C-w>p`. Then press `gp` to move the playhead to the cursor. Press `<Space><Space>` to play and `<Space><Space>` to stop.
   - *Hint:* If the terminal knows `<S-CR>` (Shift and Enter) from Enter, `<S-CR>` plays from the cursor in one step.
   - ✓ The song played from bar 5, where the melody starts.

## What we did

We moved by steps, clips, bars and tracks, with counts. The same keys had other meanings in visual mode and in the piano roll.

Previous: [First steps: the screen, play and quit](01-first-steps.md) · [All lessons](README.md) · Next: [Tracks, clips and notes](03-making.md)
