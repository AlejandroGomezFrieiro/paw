# How to add a track with a virtual instrument

<!-- tags: instrument-track -->

You can add a track that plays a virtual instrument, either the built-in
synth or a plugin, and start from one of its presets. If you want to play
the instrument from a keyboard, see
[How to connect a MIDI keyboard](connect-a-midi-keyboard.md).

## Add the track and the instrument

1. In the arrange view, press `o`, and paw adds a track below the cursor.
   Press `O` to add it above.
2. Press `grn`, type a name, for example `Bass`, and press `Enter`.
3. Press `a`, and the list of devices opens. On a track with no
   instrument, the instruments come first.
4. Type a part of the name of the instrument, and press `Enter`:
   - `synth` for the built-in synth.
   - `drums` for the built-in drum machine.
   - a part of the name of a plugin, for example `surge`. The editor of the
     plugin opens.

You can also type `:device.add synth`, or `:device.add surge`.

If you want to hear an instrument in the list before you add it, select it
and press `Ctrl-Space`.

## Start from a preset

1. Press `<Space>dd`, and the device panel shows the devices of the track.
2. Put the cursor on the row of the instrument, and press `c`. The list of
   presets opens.
3. Type a part of the name, for example `pluck`, and press `Enter`.

To try the presets one after the other, press `]p` and `[p`.

## Add notes to hear it

1. Press `<C-w>p` to return to the arrange view.
2. Press `i` and `Enter`, and paw opens a new clip in the piano roll, in insert mode.
3. Press `4l` to draw a note of one beat, and then press `Esc`.
4. Press `gs` to put the playhead at the start, and then press `<Space><Space>`, and the note plays. You need `gs` first because `<Space><Space>` plays from the cursor, and the cursor is now after the note.

In the graphical window, click `+ add a device` under the devices of the
device panel, type the name in the picker and press `Enter`. To make an
empty clip, double-click the timeline.

## See also

- [How to use your own plugins](use-your-own-plugins.md)
- [How to change the sound of an instrument](change-the-sound-of-an-instrument.md)
- [Devices](../reference/devices.md): the built-in devices and their presets.
