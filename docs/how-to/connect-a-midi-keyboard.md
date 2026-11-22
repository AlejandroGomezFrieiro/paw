# How to connect a MIDI keyboard

<!-- tags: midi-keyboard -->

You can play an instrument in paw from a MIDI keyboard, and you can check
that paw sees the keyboard. The steps assume that paw runs with an audio
device, because paw opens the MIDI ports only with an audio device and not
with `--audio null`.

## Check that paw sees the keyboard

1. Plug the keyboard into the computer with its USB cable.
2. Type `:midi.inputs`. A window lists each MIDI port, for example
   `Keystation 49 MIDI 1`, with `open` next to it.
3. Press `Esc` to close the window.

If the keyboard is not in the list, type `:checkhealth audio`. If it says
"no MIDI inputs", plug the keyboard in again, or start paw after you plug
it in. paw also finds ports that appear later, while it runs.

## Play an instrument

1. Press `o` to add a track.
2. Press `a`, type `synth` and press `Enter`. You can also add a plugin
   (see [How to add a track with a virtual instrument](add-an-instrument-track.md)).
3. Play some keys. You hear the synth, and the meter of the track moves.

The selected track plays the keyboard, so when you go to a different track
with `j` or `k`, the keyboard plays that track instead.

When a track is armed (`r`), only the armed tracks play the keyboard. A
track with its monitor on (`<A-i>`) also plays the keyboard. If you want
only the armed and monitored tracks to play, type
`:set midi_follows_selection false`.

## Take one keyboard only

By default, a track plays the notes from all MIDI ports and all channels.
To take one keyboard only, give the track its port:

1. Select the track and press `I`, and the list of the inputs opens.
2. Under MIDI, select the port of your keyboard and press `Enter`.
3. To take one channel only, press `I` again and select the channel.

You can also type `:track.midi Keystation ch=1`, with a part of the name
of the port.

If you want paw to leave the other ports alone, type
`:midi.select Keystation`, and paw opens only the ports with that name.

To record what you play, see [How to record MIDI from a keyboard](record-midi-from-a-keyboard.md).
The same steps record MIDI on a track that has no audio input.

To enter notes one at a time, with no need to play in time, see
[How to enter notes from a MIDI keyboard](enter-notes-from-a-midi-keyboard.md).

To move faders and parameters with the knobs of the keyboard, see
[How to map a MIDI controller](map-a-midi-controller.md).

## See also

- [MIDI input](../reference/midi.md#midi-input): the ports, MIDI 2.0, ports that go away.
- [Step input](../reference/piano-roll.md#step-input): notes from the keyboard, one at a time.
- [Recording](../reference/recording.md#the-input-of-a-track): the input of a track.
