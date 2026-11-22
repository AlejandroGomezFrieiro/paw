# How to play a hardware synth from a track

You can send the notes of a track to a synth on a MIDI port. The steps
assume that paw runs with an audio device, and each form and field is in
[MIDI](../reference/midi.md#midi-output).

1. Plug the synth into the computer.
2. Select the track and press `I`. Under MIDI out, select the port and the
   channel, or type `:track.midi_out UM-ONE 2`.
3. Play the song. The synth plays the notes and controllers of the track,
   in time with the other tracks.

If the synth supports MPE, and you want the bends of each note, type
`:track.midi_out UM-ONE 2 mpe`.

If the synth supports MIDI 2.0, and the kernel has `CONFIG_SND_SEQ_UMP`,
paw sends MIDI 2.0 by itself.

To play a software synth that reads a MIDI port, make a port of paw with
`paw.midi.open_output("To Surge")`. Connect the synth to `paw out: To
Surge`, and select `To Surge` as the MIDI out of the track.

A render does not send MIDI. If you want to keep the sound of the synth,
record its audio output on a track.
