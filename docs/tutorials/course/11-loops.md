<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 11: Loops, marks and jumps

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 11`.*

In this lesson, we loop the chorus of a song with a click. Then we jump between marks and loop two bars of the verse.

When you work on a part, you hear it again and again: this is the loop. You can enable and disable the loop, and set it with the `gl` operator. The ruler shows it.

In a long song, you must move quickly. `/` finds clips and tracks by name. `m` sets a mark and `'` returns to it. Other keys return to the position before a jump.

This song has an intro, a verse and a chorus.

## The idea

`gL` enables and disables the loop. `gl` with a motion or an object sets the loop (`glic`, `gl2W`). `il` is the loop as a text object (`yil`, `dil`). `gm` is the metronome. `gs` moves the playhead to the start and `gp` moves it to the cursor.

`ma` sets a mark and `'a` returns to it. `''` returns to the position before the last jump. `<C-o>` `<C-i>` move back and forward through jumps. `/name` finds a clip or a track. `n` `N` go to the next and the previous match. `*` goes to the next clip with the same name.

## If you know Vim

Marks, `''`, `<C-o>` `<C-i>`, `/` `n` `N` and `*` are from Vim. Each view has its own marks: the arrange view has some and the piano roll has others. When a track moves, its marks move with it. `:marks` shows them.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. `gL` enables and disables the loop. The `loop` in the status line comes on, and the ruler shows the loop. Press `gL`.
   - ✓ The loop is on, over the first two bars.
2. `/` finds a clip or a track by its name. Type `/chorus` and press `<CR>`.
   - ✓ The cursor is on the chorus. `n` goes to the next match, the chorus of Bass.
3. `gl` is the loop operator. Press `glic` to loop the clip under the cursor.
   - ✓ The chorus is the loop.
4. `gm` enables the metronome (the click). Press `gm`. Then press `gp` to move the playhead to the cursor, and `<Space><Space>` to play. `<Space><Space>` stops.
   - ✓ The chorus played with a click.
5. Press `gm` to disable the click.
   - ✓ The click is off.
6. `ma` sets mark a at the cursor. Press `ma`.
   - ✓ Mark a is on the chorus. `:marks` shows the marks.
7. Move to a different position: press `G` (the last track) and `0` (the start). Then press `'a` to jump to the mark.
   - *Hint:* `'` is the apostrophe key.
   - ✓ The cursor is on the chorus of Drums again.
8. `''` returns to the position before the jump. Press `''`.
   - ✓ The cursor is at the start of Lead, where it was before `'a`. `''` again returns to the chorus. `<C-o>` goes further back.
9. `gl` also accepts motions. Press `3|` to go to bar 3. Then press `gl2W` to loop two bars from there.
   - ✓ The loop is the first two bars of the verse.
10. Listen. Press `gp` and `<Space><Space>`. `<Space><Space>` stops.
   - ✓ Two bars of the verse play again and again.

## What we did

We set the loop with `gL`, `glic` and `gl2W`, and the click with `gm`. We used `/` to find, and `ma` `'a` `''` to jump.

Previous: [The mix: faders, pan, buses, sends, automation](10-mixing.md) · [All lessons](README.md) · Next: [Record audio and MIDI](12-recording.md)
