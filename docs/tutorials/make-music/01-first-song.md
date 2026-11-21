# Lesson 1: Your first song

*This lesson takes about 20 minutes.*

In this lesson, we make a loop of four bars at 100 BPM. It has a drum beat,
a bass line and four chords. We write the notes in the piano roll, play
the loop, and save it as a project.

## Start paw

1. Open a terminal in your folder for songs. Type `paw` and press Enter.
   - paw shows an empty project. The bottom line shows `NORMAL·arrange`:
     the arrange view gets the keys.
2. Type `:tempo 100` and press Enter.
   - The status line shows `100 bpm`.

A key in normal mode does an action at the cursor. A command starts with
`:` and ends with Enter. `<Esc>` cancels a command.

## Make the drum track

1. Press `o` to add a track.
   - A new track shows, and the cursor is on it.
2. Press `grn`, then `<C-u>` (Ctrl and u) to clear the name. Type `Drums`
   and press Enter.
   - The track has the name Drums.
3. Press `a`, type `drums` and press Enter.
   - `a` opens the list of devices. paw adds the built-in drum kit and
     says `added Drums to Drums`.
4. Press `i`, then `<Esc>`.
   - `i` makes an empty clip at the cursor and opens it in the piano roll.
     `<Esc>` leaves insert mode, and the piano roll stays open below the
     tracks.

## Write the beat

The piano roll has one row for each pitch, and one column for each
sixteenth note. The drum kit plays a kick on C2, a snare on D2 and a
closed hi-hat on F#2. The keys at the left of the piano roll show these
names.

1. Press `<C-d>` two times.
   - `<C-d>` moves the cursor down one octave. The title row shows `C2`.
2. Press Enter to add a kick. Press `8l`, then Enter.
   - `8l` moves eight steps to the right, to beat 3. The clip now has a
     kick on beats 1 and 3.
3. Press `2k` (up to D2) and `4h` (back to beat 2). Press Enter. Press `8l`
   and Enter.
   - The clip has a snare on beats 2 and 4.
4. Press `4k` (up to F#2) and `0` (the start of the clip).
5. Press `i` and `l`. Then press `<Space>` and `l` seven times, and press
   `<Esc>`.
   - In insert mode, `l` draws a note one step long. `<Space>` keeps it and
     leaves a rest of one step. paw says `wrote 8 notes`: a hi-hat on each
     eighth note.
6. Press `<C-w>p` to return to the arrange view.
   - `<C-w>p` returns to the window that had the keys before. The clip
     shows the beat.
7. Press `&` three times.
   - Each `&` adds a copy of the clip after it. The drums play four bars.

If a note is in the wrong place, press `u` to undo it. Each key that
changes the project is one undo step.

## Make the bass

1. Press `o`. Press `grn` and `<C-u>`, type `Bass` and press Enter.
2. Press `a`, type `synth` and press Enter.
   - The bass track has the built-in synth.
3. Press `0` to put the cursor at the start of the song.
4. Press `i`. Then press `J` and `3-`.
   - Insert mode starts a note on C4. `J` moves it down one octave,
     and `3-` three semitones, to A2.
5. Press `16l`, then Enter.
   - The A2 is one bar long. Enter keeps it and starts the next note where
     it ends.
6. Draw the next three notes. Press `4-` and `16l`, then Enter. Press `7+`
   and `16l`, then Enter. Press `5-` and `16l`, then `<Esc>`.
   - The bass plays A2, F2, C3 and G2, one bar each.
7. Press `<C-w>p` to return to the arrange view.

## Make the chords

1. Press `o`. Press `grn` and `<C-u>`, type `Keys` and press Enter.
2. Press `a`, type `synth` and press Enter. Press `0`.
3. Press `i` and `3-` (down to A3).
4. Press `c`. Type `vi` and press Enter. Then press `16l` and Enter.
   - In insert mode, `c` makes the note a chord. `vi` is the sixth chord
     of the key, A minor in C major. Then `16l` makes all of the chord one
     bar long, and Enter keeps it.
5. Draw the next chords. After each chord, press Enter:
   - F: `c`, type `IV6`, Enter, `16l`. The `6` puts the third, A, at the
     bottom.
   - C: `c`, type `I64`, Enter, `16l`. The `64` puts the fifth, G, at the
     bottom.
   - G: `c`, type `V`, Enter, `16l`. Press `<Esc>`, not Enter, after this
     last chord.
6. Press `<C-w>p`.
   - The Keys track has four chords: Am, F, C and G.

## Play the loop

1. Press `gg` (the first track) and `0` (the start). Press `gl4W`.
   - `gl` sets the loop over what the next keys select, and `4W` is four
     bars. The status line shows `loop 1–4`.
2. Press `gs` to move the playhead to the start. Press `<Space><Space>` to play.
   - The four bars play again and again. Notice how the meters of the
     tracks move.
3. Press `<Space><Space>` to stop.

In the graphical window, the play button and a drag on the ruler do the
same.

## Save the song

1. Type `:w first-song` and press Enter.
   - paw makes the folder `first-song` and saves the song in it.
   - paw says `saved first-song`, and the status line shows the name of
     the project.

To open the song again later, type `paw first-song` in the same folder.
The finished song of this lesson is also in the practice project
`examples/tutorials/make-music/1-first-song.lua`. To open it, type
`:example make-music/1-first-song`.

## What we made

We made a song of four bars: a drum beat, a bass line and four chords on
the built-in instruments. We drew every note with the keyboard, played it
in a loop, and saved it. That is the base of the song for the next
lessons.

Next: [Play a synth from a MIDI keyboard](02-play-a-midi-keyboard.md) ·
[All lessons](README.md)

For more about the piano roll, see [The piano roll](../../reference/piano-roll.md)
and lessons 3 and 4 of [the course](../course/README.md).
