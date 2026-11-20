# The device panel

<!-- tags: devices-panel -->

The device panel shows the devices of a track. `,d` shows it. It is a grid
of rows: the heading of a device, then its parameters, then the next
device. Under the last device are the add line, the track that this track
plays into, and its sends.

The terminal and the graphical window show the same panel, from the same
Lua view (`runtime/lua/paw/views/devices.lua`). The window paints its parts
as widgets: sliders, a power button, buttons with icons.

## Keys

| Keys | Effect |
| --- | --- |
| `j` `k` | Go to the next and the previous row. |
| `w` `b` | Go to the next and the previous device. |
| `e` | Goes to the last parameter of the device. |
| `gg` `G` | Go to the first and the last row. |
| `+` `-` | Change the parameter by 1/100 of its range (`10+`, `5 Ctrl-x`). On the row of a device, change its wet mix. |
| `c` | Types the value of the parameter in its own unit. A choice takes its name. `-6` is the value -6. `+=2` and `-=3` step from the value. |
| `x` | Sets the parameter to its default. On the row of a device, removes the device. |
| `Enter`, `gC` | Open the curve of the parameter in the [curve editor](curve-editor.md). On the row of a device, `Enter` shows the window of the device. |
| `A` | Automates the parameter (`:param.automate`): makes its lane with a point at its value, at the beat of the arrange cursor, and shows the lanes of the track with the cursor on the new lane. |
| `c` | On the row of a device: chooses a preset. |
| `ge` | Shows the window of the plugin. |
| `[p` `]p` | Step through the presets. |
| `,w` | Saves a preset. |
| `,W` | Makes the preset the default of the device. |
| `dd` | Cuts a device. On a parameter, sets it to its default. |
| `yy` | Copies a device. |
| `p` `P` | Paste a device after or before the cursor, also on a different track. |
| `y` over parameters | Copies their settings. Then `p` puts them on the device under the cursor: `yj`, then `p` on a different synth copies two settings. |
| `gcc` | Bypasses the device. |
| `V` | Selects several devices or parameters, for the keys above. |
| `.` | Repeats the last change. |
| `Alt-j` `Alt-k` | Move the device down or up the chain. |
| `f` | Finds a parameter. |
| `t` | Goes to the last parameter that you changed. |
| `gS` | Chooses the track that the device listens to, as its side-chain. |
| `O` | Chooses where the further output pairs of the device play. |
| `K` | Describes the device or the parameter. |
| `s` | Solos the track. |
| `:device.copy_to <track>` | Copies the selected device to a track. |
| `:device.move_to <track>` | Moves the selected device to a track. |
| `\p`, `:devices.pin` | Pins the panel to the track that it shows. Again: the panel follows the cursor track. `:devices.pin Bass` pins it to the track Bass. |

## Two panels on two tracks

The device panel shows in any number of windows. Each window has its own
row, scroll and track. A panel follows the cursor track until you pin it.
A pinned panel shows its track, wherever the cursor goes. Its title says
`pinned`.

- `:vs devices://Bass` puts a second panel beside this window, pinned to the track Bass. A number also names a track: `devices://3`.
- `:e devices://Bass` pins the panel in this window.
- In a pinned panel, the keys and the commands act on its track. For example, `a` adds a device to that track, and `p` pastes there.
- A saved layout and the project keep the track of a pinned panel.

## The parts of a row

| Row | Parts, from the left |
| --- | --- |
| Heading of a device | The name. The preset, or a caret when no preset is loaded. At the right: the buttons `⧉` `↑` `↓` `×`, the format, the wet mix, the outputs and the side-chain, and the power chip (`on` or `off`). A device that does not run shows its state in place of the chip. |
| Picture | What a built-in effect does: the curve of the equalizer, the gain reduction, the loudness, the needle of the tuner. |
| Parameter | The name, a slider, the value in its unit, and, when the panel is 36 columns wide or more, `A` (automate) and `L` (learn). |
| Add line | `+ add a device`. |
| Output | The track that this track plays into, and `+ send`. The master has no output row. |
| Send | The track, a slider for the level, the level in dB, `pre` and `×`. |

A parameter that a lane moves shows the value of the lane at the playhead.
In the graphical window, its slider is amber and moves while the song
plays.

## The pointer

The pointer works in the same way in the terminal and in the graphical
window.

| Gesture | Effect |
| --- | --- |
| Click a row | Selects the row. |
| Click or drag a slider | Sets the parameter. With `Shift`, the drag moves in small steps. While you hold it, the slider writes automation in touch mode. |
| Double-click a slider | Sets the parameter to its default. |
| `Ctrl` and the wheel over a slider | Changes the parameter in steps of 1/100. |
| Wheel | Moves the cursor from row to row. |
| Right-click a row | A menu: automate the parameter, edit its curve, and what the language servers say about it. |
| Drag the name of a device up or down | Moves the device. On a later device, it goes after it. On an earlier device, it goes before it. With `Ctrl`, the drag copies it. |
| `on`, `off` | Bypasses the device, or lets it play again. |
| The preset, or the caret | A menu of the presets: load one, save one, make one the default. |
| `⧉` `↑` `↓` `×` | Show the window of the plugin, move the device up or down the chain, remove it. |
| `outs`, `key` | A menu of where the further outputs play, or of the track that the device listens to. |
| `offline: o`, `stopped: gR restarts` | Puts the plugin online again, or starts it again. |
| `A`, `L` | Automates the parameter, as the menu does. Learns a MIDI controller for it. |
| `+ add a device` | Opens the picker of devices, as `a` does. |
| The output, `+ send` | A menu of the tracks to play into, or to send to. |
| Slider of a send | Sets the level, from -60 dB to +6 dB. A double-click sets 0 dB. |
| `pre`, `×` of a send | Takes the send before the fader. Removes the send. |
