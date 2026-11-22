# How to enter notes from a MIDI keyboard

<!-- tags: step-input-how-to -->

You can enter notes one note or one chord at a time from a MIDI keyboard, with no need to play in time. The steps assume that paw sees the keyboard (see [How to connect a MIDI keyboard](connect-a-midi-keyboard.md)) and that the track has a MIDI clip. The rules are in [Step input](../reference/piano-roll.md#step-input).

## Choose the keyboard

1. Select the track and press `I`.
2. Under MIDI, select the port of the keyboard and press `Enter`. If you do not choose a port, step input takes the notes of every port.

## Enter notes and chords

1. Press `Enter` on the clip to open it in the piano roll, and move the cursor to where the notes start.
2. Press `I` to start step input. The title shows `STEP`, and a caret shows where the next note goes.
3. Type `=` and a note value, for example `=8` for eighth notes, `=8.` for dotted eighths or `=8t` for triplets. The value is the length of each note and rest that follows.
4. Play a key. The note enters at the caret with the velocity of the key, and the caret moves to its end.
5. To enter a chord, hold all its keys together, and release them all before the next key.
6. To rest for one step, press `<Space>`. For three steps, press `3<Space>`.
7. If you entered a wrong note, press `<BS>` to take it back and play again.
8. Press `<Esc>` to write all the notes and leave insert mode. Press `u` to undo them all at once.

If the title shows `STEP (paused: playing)`, stop the song first, because step input doesn't enter notes while the song plays or records. If `I` says that there is no MIDI input, check the port with `:midi.inputs` and choose it as in the first section. Step input stays on, and notes that arrive later enter.

## Use the sustain pedal

The sustain pedal works with no setup. With no key held, a press of the pedal rests one step. While you hold keys, a press makes those notes one step longer.

## Use a pad or a key as a control

1. Type `:step.learn rest` and press `Enter`.
2. Press the pad or the key of the keyboard. paw says that it now does `rest` in step input.
3. Start step input with `I`. The pad now rests one step, and it makes no sound and enters no note.

To bind another action, type `:step.learn` and the name of the action, for example `tie` or `dur.8`. Type `:step.controls` to list the controls, and press `Alt-d` on one to remove it. The actions are in [Controls of the controller](../reference/piano-roll.md#controls-of-the-controller).

## See also

- [Step input](../reference/piano-roll.md#step-input): the keys, the title, `step_velocity` and the controls.
- [How to record MIDI from a keyboard](record-midi-from-a-keyboard.md): when you want to play in time.
