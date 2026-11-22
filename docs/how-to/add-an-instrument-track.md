# How to add a track with a virtual instrument

<!-- tags: instrument-track -->

This guide shows you how to add a track that plays a virtual instrument.
The instrument can be the built-in synth or a plugin, with a preset. To
play the instrument from a keyboard, see
[How to connect a MIDI keyboard](connect-a-midi-keyboard.md).

## Add the track and the instrument

1. In the arrange view, press `o`. paw adds a track below the cursor.
   Press `O` to add it above.
2. Press `grn`, type a name, for example `Bass`, and press `Enter`.
3. Press `a`. The list of devices opens. On a track with no instrument,
   the instruments are first.
4. Type a part of the name of the instrument, and press `Enter`:
   - `synth` for the built-in synth.
   - `drums` for the built-in drum machine.
   - a part of the name of a plugin, for example `surge`. The editor of the
     plugin opens.

You can also type `:device.add synth`, or `:device.add surge`.

To hear an instrument in the list before you add it, select it and press
`Ctrl-Space`.

## Start from a preset

1. Press `<Space>dd`. The device panel shows the devices of the track.
2. Put the cursor on the row of the instrument, and press `c`. The list of
   presets opens.
3. Type a part of the name, for example `pluck`, and press `Enter`.

To try the presets one after the other, press `]p` and `[p`.

## Add notes to hear it

1. Press `<C-w>p` to return to the arrange view.
2. Press `i` and `Enter`. paw opens a new clip in the piano roll, in insert mode.
3. Press `4l` to draw a note of one beat, then press `Esc`.
4. Press `gs` to put the playhead at the start, then `<Space><Space>`. The note plays. (`<Space><Space>` plays from the cursor, and the cursor is now after the note.)

In the graphical window, click `+ add a device` under the devices of the
device panel, type the name in the picker and press `Enter`. To make an
empty clip, double-click the timeline.

## See also

- [How to use your own plugins](use-your-own-plugins.md)
- [How to change the sound of an instrument](change-the-sound-of-an-instrument.md)
- [Devices](../reference/devices.md): the built-in devices and their presets.
