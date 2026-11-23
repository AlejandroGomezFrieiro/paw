<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 12: Record audio and MIDI

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 12`.*

In this lesson, we record an audio take and a MIDI take on two tracks, over a drum beat.

A track records its input, which is either audio from an input of your sound card, e.g., a microphone or a guitar, or notes from a MIDI keyboard. To record, first arm the tracks that you want to record. Second, start the recording and play, and third, stop the recording. Each armed track gets a new clip at the position where the recording started. A track with an audio input records audio, and an armed track with no input records MIDI.

For the first part of the lesson, you need a microphone or another input, and for the second part, you need a MIDI keyboard. If you do not have them, read the steps and press `<Space>hn` to skip a step. The recordings of the practice project go in the folder of the tutor.

## The idea

In the arrange view, `I` shows the inputs that the track can use. The audio inputs are each channel of the input device and each pair of channels, for example `UR22mkII · 1/2`, and there is also an entry for no audio input. The MIDI inputs are all ports, one port, or one MIDI channel.

`<A-i>`, or the `I` in the header, monitors the input, so you hear the input, but paw does not record it.

`r` arms the track, and `R` starts the recording from the cursor. `R` again stops the recording, but the song continues to play until you press `<Space><Space>`.

`:midi.inputs` shows the MIDI ports, and `:midi.select` selects some of them. `:audio` selects the input and output devices. Each take is one undo step.

## If you know Vim

In paw, `r` arms a track instead of replacing a character, and `R` records instead of starting replace mode.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. The cursor is on Voice, a track with no device, and `I` shows the inputs that the track can use. Press `I`, and type some letters of the input of your microphone. Type `1/2` for the first pair of channels, or `· 1` for the first channel, and press `<CR>`.
   - *Hint:* If the list has no channels, no input device is open. `:audio` shows the devices, and you can select one there.
   - ✓ Voice gets its sound from the input that you selected, and the header shows the input and its level. With `<A-i>`, you hear the input without a recording.
2. `r` arms the track for a recording, and its `R` becomes red. Press `r`.
   - ✓ The track is armed, and you also hear the input of an armed track.
3. `R` starts the recording from the cursor, as `<Space><Space>` plays from it. Press `R`, and sing or play for some seconds. Then press `R` to stop the recording, and `<Space><Space>` to stop the song.
   - *Hint:* Press `R` before `<Space><Space>`. If you press only `<Space><Space>`, record mode stays on, with `rec` lit in the status line, and the next `<Space><Space>` records again.
   - ✓ A new audio clip with your take shows where the recording started, and the clip shows its waveform.
4. Now we record MIDI. Press `r` to disarm Voice, `j` to go to Keys, and `r` to arm Keys.
   - *Hint:* `:midi.inputs` shows the MIDI ports that paw finds.
   - ✓ Keys is armed and has no audio input, so it records MIDI. When you play your keyboard, you hear the synth.
5. Press `0` to put the cursor at the start, and `R` to record. Play some notes on your MIDI keyboard, and then press `R` and `<Space><Space>` to stop.
   - ✓ A MIDI clip contains the notes that you played, and `<CR>` on the clip opens it in the piano roll.
6. Press `r` to disarm Keys. Then press `gs` and `<Space><Space>` to listen, and `<Space><Space>` to stop.
   - ✓ Your recordings play with the drums.

## What we did

We selected an input with `I`, armed the track with `r`, recorded with `R` and stopped with `<Space><Space>`, and we made an audio take and a MIDI take.

- Previous: [Loops, marks and jumps](11-loops.md)
- Next: [Save and export](13-saving.md)
- [All lessons](README.md)
