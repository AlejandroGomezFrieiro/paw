# How to add an effect and change its settings

You can put an effect on a part, such as an EQ, a compressor, a reverb or
a delay, and then change its settings with the keys of the device panel.
The built-in effects are listed in [Devices](../reference/devices.md), and
each key of the panel is in [The device panel](../reference/device-panel.md).

## Add the effect

1. Put the cursor on the part in the arrange view or in the mixer.
2. Press `a`. A list of the devices opens, with the built-in devices and
   the plugins that paw found.
3. Type a part of the name, for example `Compressor`, and press `Enter`.
   paw adds the effect at the end of the chain of the part.

The built-in effects include `eq`, `compressor`, `reverb`, `delay`,
`chorus`, `saturation`, `gate` and `limiter`. A plugin, for example a
VST3 or CLAP compressor, is in the same list.

## Change a setting

1. Press `<Space>dd` to show the device panel. It shows the devices of the
   part, each with its settings below its name. Press `w` to go to the
   next device, and `b` to go to the previous device.
2. Go to the setting:
   - To find a setting by name, press `f`, type a part of the name, for
     example `Threshold`, and press `Enter`.
   - To go from setting to setting, press `j` and `k`.
3. Change the value:
   - Press `+` and `-` to change the setting in small steps. A count gives
     more steps, for example `10+`.
   - To type a value, press `c`, type the value, for example `4` for a
     ratio of 4:1, and press `Enter`. For a value below zero, type `=-24`.
4. To put a setting back at its default, press `x` on it.

## Use a preset

1. Go to the row of the device name with `b`.
2. Press `c`, and a list of the presets of the device opens. Choose one and
   press `Enter`.
3. To step through the presets, press `]p` and `[p`.

To save your settings as a preset, press `<Space>dw`.

## Compare and remove

- To hear the part without the effect, press `gcc` on the device. Press
  `gcc` again to hear the effect again.
- To remove the effect, press `x` on the row of the device name. Press `u`
  to get it back.

To open the window of a plugin, press `Enter` on the row of its name, or
press `ge`.

In the graphical window, each device is a card in the device panel, and
you drag a slider to change a setting.
