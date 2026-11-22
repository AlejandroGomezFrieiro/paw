<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 11: Loops, marks and jumps

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 11`.*

In this lesson, we loop the chorus of a song with a click, and then we jump between marks and loop two bars of the verse.

The loop plays one part of the song again and again while you work on it. You can enable and disable the loop, and set it with the `gl` operator, and the ruler shows the loop.

In a long song, you need keys that move quickly. `/` finds clips and tracks by name, and `m` sets a mark that `'` returns to. Other keys return to the position before a jump.

The song in the practice project has an intro, a verse and a chorus.

## The idea

`gL` enables and disables the loop, and `gl` with a motion or an object sets the loop, e.g., `glic` or `gl2W`. `il` is the loop as a text object, e.g., `yil` or `dil`. `gm` is the metronome. `gs` moves the playhead to the start, and `gp` moves it to the cursor.

`ma` sets a mark and `'a` returns to it, and `''` returns to the position before the last jump. `<C-o>` and `<C-i>` move back and forward through jumps. `/name` finds a clip or a track, and `n` and `N` go to the next and the previous match. `*` goes to the next clip with the same name.

## If you know Vim

Marks, `''`, `<C-o>` `<C-i>`, `/` `n` `N` and `*` come from Vim. Each view has its own marks, so the marks of the arrange view are not the marks of the piano roll. When a track moves, its marks move with it, and `:marks` shows the marks.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. `gL` enables and disables the loop. When the loop is on, the status line shows `loop`, and the ruler shows the loop. Press `gL`.
   - ✓ The loop is on, over the first two bars.
2. `/` finds a clip or a track by its name. Type `/chorus` and press `<CR>`.
   - ✓ The cursor is on the chorus, and `n` goes to the next match, which is the chorus of Bass.
3. `gl` is the loop operator. Press `glic` to loop the clip under the cursor.
   - ✓ The loop is now over the chorus.
4. `gm` enables the metronome (the click). Press `gm`, and then press `gp` to move the playhead to the cursor and `<Space><Space>` to play. Press `<Space><Space>` again to stop.
   - ✓ The chorus played with a click.
5. Press `gm` to disable the click.
   - ✓ The click is off.
6. `ma` sets mark a at the cursor. Press `ma`.
   - ✓ Mark a is on the chorus, and `:marks` shows the marks.
7. Move to a different position. Press `G` (the last track) and `0` (the start), and then press `'a` to jump to the mark.
   - *Hint:* `'` is the apostrophe key.
   - ✓ The cursor is on the chorus of Drums again.
8. `''` returns to the position before the jump. Press `''`.
   - ✓ The cursor is at the start of Lead, where it was before `'a`. `''` again returns to the chorus, and `<C-o>` goes further back.
9. `gl` also accepts motions. Press `3|` to go to bar 3, and then press `gl2W` to loop two bars from there.
   - ✓ The loop is now over the first two bars of the verse.
10. Press `gp` and `<Space><Space>` to listen, and `<Space><Space>` again to stop.
   - ✓ Two bars of the verse play again and again.

## What we did

We set the loop with `gL`, `glic` and `gl2W`, and the click with `gm`. We used `/` to find clips, and `ma`, `'a` and `''` to jump.

- Previous: [The mix: faders, pan, buses, sends, automation](10-mixing.md)
- Next: [Record audio and MIDI](12-recording.md)
- [All lessons](README.md)
