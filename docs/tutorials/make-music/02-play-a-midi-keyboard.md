# Lesson 2: Play a synth from a MIDI keyboard

*The lesson takes about 15 minutes. You need a MIDI keyboard.*

In this lesson, we add a lead synth to the song of lesson 1 and play it
live from a MIDI keyboard. Then we record a melody over the loop and put
the notes on the grid.

## Open the practice project

1. Connect the MIDI keyboard before you start paw.
2. Start paw in your folder for songs. Type
   `:example make-music/2-midi-keyboard` and press Enter.

   - paw opens the song of lesson 1, with the parts Drums, Bass and Keys
     and the loop over four bars.

## Add the lead

1. Press `G` to go to the last part, Keys.
2. Press `o`. Press `grn` and `<C-u>`, type `Lead` and press Enter.
3. Press `a`, type `synth` and press Enter.
   - The Lead part has a synth.

## Choose the MIDI input

1. Press `I`.
   - A list of the inputs of the part opens, with the audio inputs, the
     MIDI ports and the MIDI channels.
2. Type some letters of the name of your keyboard, for example `Keystation`.
   Press Enter.
   - paw says `Lead ← MIDI · Keystation`. The part now plays only what
     this keyboard sends.

If the list has no MIDI port for your keyboard, press `<Esc>`. Then type
`:midi.inputs` to see the ports that paw finds.

## Play live

1. Press `r` to arm the part.
   - The `R` in the header of the part is lit. An armed part plays the
     notes that come in.
2. Play some notes on the keyboard.
   - You hear the lead synth, and the meter of the part moves.
3. Press `<Space><Space>` to play the loop, and play along with it. Press
   `<Space><Space>` to stop.

## Record a take over the loop

1. Press `0` to move the cursor to the start of the song.
2. Press `R` to record from the cursor. Play a melody over the four bars.
3. When the playhead returns to bar 1, press `R` to stop the recording.
   Then press `<Space><Space>` to stop the song.
   - A clip with the name `take 1` shows on the Lead part, and it holds
     the notes that you played.

If you continue to play past the middle of bar 2, paw keeps a second
take. Lesson 3 shows how to use takes.

## Quantize the take

1. With the cursor on the take, press Enter.
   - The take opens in the piano roll. The notes start a little before or
     after the lines of the grid, as you played them.
2. Press `=ie`.
   - `=` puts notes on the grid, and `ie` is every note of the clip. Each
     note now starts and ends on a sixteenth note.
3. Press `u`.
   - The notes return to where you played them, and paw says
     `undid Snap notes to the grid`.
4. Press `<C-r>` (Ctrl and r) to redo.
   - The notes are on the grid again.

To put the notes on a grid of eighth notes instead, type
`:%quantize 1/8`.

## Listen and save

1. Press `<C-w>p` to return to the arrange view. Press `r` to disarm the
   lead.
2. Press `gs` and `<Space><Space>`.
   - The lead plays your melody with the drums, the bass and the chords.
3. Press `<Space><Space>` to stop.
4. Type `:w with-lead` and press Enter.

## What we made

We played a synth from a MIDI keyboard, recorded a melody over the loop,
and put the melody on the grid. With undo and redo, we heard the take
before and after the change.

- Previous: [Your first song](01-first-song.md)
- Next: [Record a guitar](03-record-a-guitar.md)
- [All lessons](README.md)

For more, see [MIDI](../../reference/midi.md) for the MIDI ports and
[Recording](../../reference/recording.md) for the inputs and the takes.
