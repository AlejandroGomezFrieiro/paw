# How to change the sound of an instrument

<!-- tags: change-sound -->

This guide shows you how to change the sound of an instrument or an
effect on a track. You can change its parameters in paw, choose a preset,
or use the editor of the plugin. For each key, see [The device panel](../reference/device-panel.md).

## Change a parameter

1. Put the cursor on the track, and press `<Space>dd`. The device panel shows
   each device of the track, with its parameters under it.
2. Press `j` and `k` to go to a parameter, for example `cutoff`.
3. Press `+` or `-` to change it by one percent of its range. A count
   changes it more: `10+`.
4. To type a value, press `c`, type the value in the unit of the
   parameter, for example `800`, and press `Enter`.
5. To give the parameter its default value again, press `x`.

To find a parameter of a plugin with many parameters, press `f` and type
a part of its name.

## Choose a preset

1. In the device panel, put the cursor on the row of the device.
2. Press `c`. The list of presets opens: your presets first, then the
   presets of the device.
3. Type a part of the name and press `Enter`. To hear a preset before you
   choose it, press `Ctrl-Space`.

To try the presets one after the other, press `]p` and `[p`. The name of
the preset shows next to the name of the device.

## Keep your sound as a preset

1. In the device panel, put the cursor on the device.
2. Press `<Space>dw`. Type a name and press `Enter`.

The preset is now first in the list of presets of that device, in all
projects.

## Use the editor of the plugin

1. Press `ge` on the track, or on the device in the panel. The editor of
   the plugin opens in a window of its own.
2. Change the sound in the editor. paw reads back each change, and the
   panel shows the new value.
3. Press `ge` again to close the editor.

In the graphical window, each device is a card with its parameters. Drag a
parameter, or click the name of the preset between `◀` and `▶`.

## See also

- [Devices](../reference/devices.md): the built-in devices, presets, wet and dry.
- [Plugins](../reference/plugins.md#editors): editors that do not show.
- [How to map a MIDI controller](map-a-midi-controller.md): turn a parameter with a knob.
