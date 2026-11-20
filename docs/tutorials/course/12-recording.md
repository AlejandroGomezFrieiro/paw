<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 12: Record audio and MIDI

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 12`.*

In this lesson, we record an audio take and a MIDI take on two tracks, over a drum beat.

A track records its input. This is audio from an input of your sound card (a microphone, a guitar), or notes from a MIDI keyboard. Arm the tracks that must record, start the recording, play, and stop. Each armed track gets a new clip at the position where the recording started.

A track with an audio input records audio. An armed track with no input records MIDI. For the first part, you need a microphone or a different input. For the second part, you need a MIDI keyboard. If you do not have them, read the steps, and press `<Space>hn` to skip a step. The recordings of this practice project go in the folder of the tutor.

## The idea

In the arrange view, `I` shows the inputs that the track can use. These are no audio input, each channel of the input device, and each pair of channels (for example `UR22mkII · 1/2`). They are also MIDI from all ports or from one port, and one MIDI channel. `<A-i>`, or the `I` in the header, monitors the input: you hear it, but paw does not record it.

`r` arms the track. `R` starts the recording from the playhead. `R` again stops the recording, but the song continues to play. Then `<Space><Space>` stops it.

`:midi.inputs` shows the MIDI ports and `:midi.select` selects some. `:audio` selects the input and output devices. Each take is one undo step.

## If you know Vim

Here, `r` arms a track. It does not replace text. `R` records. It is not replace mode.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. The cursor is on Voice, a track with no device. `I` shows the inputs that it can use. Press `I`. Type some letters of the input of your microphone. Type `1/2` for the first pair of channels, or `· 1` for the first channel. Press `<CR>`.
   - *Hint:* If the list has no channels, no input device is open. `:audio` shows the devices and lets you select one.
   - ✓ Voice gets its sound from that input. The header shows the input and its level. `<A-i>` lets you hear it without a recording.
2. `r` arms the track for a recording, and its `R` becomes red. Press `r`.
   - ✓ The track is armed. You also hear the input of an armed track.
3. `R` starts the recording from the cursor, as `<S-CR>` plays from it. Press `R`. Sing or play for some seconds. Then press `R` to stop the recording, and `<Space><Space>` to stop the song.
   - *Hint:* Press `R` before `<Space><Space>`. If you press only `<Space><Space>`, record mode stays on (`rec` is lit in the status line), and the next `<Space><Space>` records again.
   - ✓ A new audio clip with your take shows where the recording started. The clip shows its waveform.
4. Now we record MIDI. Press `r` to disarm Voice, `j` to go to Keys, and `r` to arm Keys.
   - *Hint:* `:midi.inputs` shows the MIDI ports that paw finds.
   - ✓ Keys is armed and has no audio input, so it records MIDI. Play your keyboard, and you hear the synth.
5. Press `0` to put the cursor at the start and `R` to record. Play some notes on your MIDI keyboard. Then press `R` and `<Space><Space>` to stop.
   - ✓ A MIDI clip contains the notes that you played. `<CR>` on the clip opens it in the piano roll.
6. Press `r` to disarm Keys. Then listen: press `gs` and `<Space><Space>`, and `<Space><Space>` to stop.
   - ✓ Your recordings play with the drums.

## What we did

We selected an input with `I`, armed with `r`, recorded with `R` and stopped with `<Space><Space>`. We made an audio take and a MIDI take.

Previous: [Loops, marks and jumps](11-loops.md) · [All lessons](README.md) · Next: [Save and render](13-saving.md)
