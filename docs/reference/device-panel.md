# The device panel

<!-- tags: devices-panel -->

The device panel shows the devices of a part, and `<Space>dd` shows it. It has two windows. The devices view at the top draws the chain of the part as a graph, and the inspector under it shows the parameters of the node under the cursor of the graph. The inspector gets the keys, and `Ctrl-w k` goes up to the devices view.

The terminal and the graphical window show the same panel, from the same Lua views (`runtime/lua/paw/views/devices.tl` and `runtime/lua/paw/views/inspector.lua`), and the window paints its parts as widgets, which are sliders, a power button and buttons with icons.

## The devices view

The devices view draws each device as a card of two rows, with its name and a meter on the first row, and its preset or its first parameter on the second. Arrows join the cards in the order of the signal, from `in` to `out`. A row that is too long for the window ends with `↩` and goes on in the next row after `↪`.

A split has a lane for each branch, with the name and the gain of the branch, and a rack has a frame around its devices. Splits and racks start folded, as one card with a summary. The path to the cursor opens. A split or a rack that does not fit in the window folds itself when the cursor is not in it. A window narrower than 72 columns shows an outline instead, with one row for each node.

The title of the view gives the number of devices and containers, the latency of the chain, the CPU while the song plays, and the parts that the side-chains listen to. The row under it gives the path of the cursor, for example `Vocal › Sends › 2 Throw`, and at the right a chip for a branch that is soloed (`SOLO`), for a chain that is bypassed (`BYPASS`) and for a pinned view.

A split whose kind no loaded extension defines says `⚠ absent` in its header, and a folded one says `⚠ plays branch 1`. The engine plays its first branch until the extension loads again, and `K` says why.

The keys of the devices view work as the keys of Vim work on text. A node is a device, a split or a rack, and a motion goes from node to node. An operator such as `d` takes a motion, a text object or a selection, and each change is one undo step that says what it did.

### Motions

| Keys | Effect |
| --- | --- |
| `l` `h`, `w` `b` | Go to the next and the previous node, in the order of the signal. In an open split, the cursor stops on each branch before its devices. |
| `j` `k` | Go to the same place in the branch below or above. In a narrow window, go to the next and the previous row. |
| `gg` `G` | Go to the first and the last node. |
| `^` `$` | Go to the first and the last node of the branch. |
| `0` `e` | Go to the split at the start of the branch, and to the last device of the branch. |
| `%` | Goes from a split to its last node, and back. |
| `[(` `])` | Go to the split or rack around the cursor, and to its last node. |
| `za` `zo` `zc` | Fold or open the split or the rack under the cursor, or around it. |
| `zR` `zM` | Open or fold all the splits and racks. |
| `zn{motion}` `znn` | Enters the split or the rack, so that the window shows only its inside. |
| `zw` `zW` | Show the whole chain again. |

### Operators

| Keys | Effect |
| --- | --- |
| `d` `dd` `x` | Cut nodes into a register. `2dd` cuts two nodes in series. |
| `y` `yy` | Copy nodes into a register. |
| `p` `P` | Paste the register after or before the node. |
| `gp` `gP` | Paste the register as a new branch below or above. |
| `c` | Cuts the nodes, then opens the picker of devices at their place in insert mode. `cc` on a device chooses a preset, and on a split or a branch it asks for a name. |
| `>` `<` | Move nodes later or earlier in the signal. `3>>` moves the node three places. At the end of a branch, the node goes out of the split. |
| `gc` `gcc` `~` | Bypass devices and mute branches. Again, they play. |
| `=` | Matches the output gain of each device to its input, from what played last. |
| `gs{kind}` | Wraps nodes in a split. The letter after it names the kind: `r` rack, `l` layer, `b` band, `m` mid/side, `s` left/right, `k` key, `v` velocity, `x` select and `o` outputs. A count before the letter gives the branches, as in `gs3b`. A rack asks for its name. |
| `ds` | Unwraps the split around the cursor. The branch of the cursor stays, and the other branches go into the register. |
| `cs{kind}` | Changes the kind of the split, with the letters of `gs`. |
| `gm` | Links a macro of the container to the main parameter of each device, at 25 % of its range. |
| `gM` | Makes the main parameter of the devices a macro of their container. |
| `zf{motion}` | Folds the containers that the motion covers. |
| `Alt-j` `Alt-k` | Move the node to the branch below or above, at the same place. |
| `+` `-`, `Ctrl-a` `Ctrl-x` | On a device, change its wet mix by 5 %. On a branch, change its gain by 1 dB. On a split, change its mix by 5 %. A count multiplies the step. |
| `]` `[` | On a device, change its output gain by 1 dB. On a branch, change its pan by 0.1. On a split, change its gain by 1 dB. |

### Text objects

| Keys | Effect |
| --- | --- |
| `in` | The node: a device, or a container with its inside. |
| `ab` `ib` | The branch, and the nodes of the branch. |
| `as` `is` | The split around the cursor, and its branches. A count goes out that many splits. |
| `ar` `ir` | The rack around the cursor, and its devices. |
| `im` | The devices that the macros of the container move. |
| `ie` | The entire chain. |

### Visual mode

`v` selects nodes along the signal, `V` selects whole branches, and `Ctrl-v` selects a block: the same places in several branches. An operator then acts on all the selected nodes, so `Ctrl-v` `jj` `gc` bypasses the device at one place in three branches. The title of the view says what is selected, for example `2 nodes`, `1 branch` or `2 x 3 block`, and the status line says `VISUAL`, `V-LINE` or `V-BLOCK`.

### Insert mode

`i` starts insert mode with a caret before the node, and the title says where the caret is, for example `INSERT before ▣ layer`. Each insert key adds one node at the caret, and the caret moves past it. A count before a device key adds that many devices. A count before a split key gives its branches, as in `3B`. `Escape` ends insert mode and says what was inserted, and one `u` takes back all of one insert.

| Keys | Effect |
| --- | --- |
| `c` `e` `s` `g` `l` `d` `r` `u` `m` | Insert a compressor, an EQ, a saturation, a gate, a limiter, a delay, a reverb, a utility and a meter. |
| `R` `L` `B` `M` `S` | Insert a rack, a layer split, a band split, a mid/side split and a left/right split. The caret goes into its first branch. |
| `Tab` | Chooses a device at the caret from the picker. |
| `\|` | Adds a branch to the split around the caret, and moves the caret into it. |
| `Ctrl-r` | Inserts the nodes of a register at the caret. |
| `Backspace` `Ctrl-u` | Take back the node inserted last, and all that the insert added. |
| Arrows | Move the caret along the branch and across the branches. |
| `Enter` | Goes to the inspector of the node inserted last. |
| `K` | Says what each insert key adds. |

`a` adds one device after the node from the picker. `o` and `O` add a branch below or above the node and start insert mode in it. Out of a split, they first put the node in a layer.

`paw.opt.graph_insertkeys` gives the insert keys that work, in their order. `paw.insert.add(key, {view = "devices", device = "chorus"})` adds a key, and `split = "band"` in place of `device` adds a split. See [Insert mode](insert-mode.md).

### What you hear

| Keys | Effect |
| --- | --- |
| `\s` | Solos the branch under the cursor alone. Again: no solo. |
| `\S` | The solo follows the cursor across the branches, and the title says `SOLO follows`. Again: the solo stays where it is. |
| `\b` | Bypasses the whole chain and keeps the state of each device. Again: each device plays as it was. |
| `:ab.store`, `\a` | `:ab.store` keeps the chain as a second variant, and `\a` flips between the two variants. The title says `B` while the second plays. |
| `s` `M` | Solo and mute the part. |

paw keeps the states of `\b` and the second variant of `\a` only until it quits, and the project does not save them. After `u` takes back a `\b`, the next `\b` bypasses the chain again.

### Other keys and commands

| Keys | Effect |
| --- | --- |
| `Enter` | Goes to the inspector. |
| `K` | Describes the node. On a split: its kind, its branches with their gain, and what the engine plays. |
| `\p`, `:devices.pin` | Pins the view to the part that it shows, as in the inspector. |
| `:wrap <kind> [branches]` | Wraps the node or the selection in a split. `:wrap band 120 2k` makes three bands with crossovers at 120 Hz and 2 kHz, and `:wrap layer 3` makes three branches. |
| `:unwrap`, `:unwrap all` | Unwraps the split around the cursor and keeps the branch of the cursor. `all` puts all the branches in series. |
| `:branch add [name]`, `:branch remove`, `:branch solo` | Add a branch to the split, remove the branch of the cursor, and solo it. |
| `:xover <hz>...` | Sets the crossovers of the band split, as in `:xover 120 2k`. |
| `:zone <range>` | Sets the notes or the velocities that the branch hears, as in `:zone C1-B2` or `:zone 64-127`. |
| `:macro <name>` | Adds a macro to the split or the rack. |
| `:macro.link <param> [depth]` | Links the first macro of the container to a parameter of the device, with a depth in percent. |

A click on a card puts the cursor on it.

## The inspector

The inspector is a grid of rows, with the heading of a device, then its parameters, then the next device. On a device, it shows that device and the devices in series with it, so on a part with no splits it shows the whole chain. On a split or a rack, it shows its macros, each with a slider, and the parameters that each macro moves. On a branch, it shows the gain and the pan of the branch, then its devices. Under the last row are the add line, the part that this part plays into, and its sends.

The row of the inspector and the cursor of the devices view go together. When the row goes to another device, the cursor of the devices view goes there too.

## Keys of the inspector

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
| `A` | Automates the parameter (`:param.automate`): makes its lane with a point at its value, at the beat of the arrange cursor, and shows the lanes of the part with the cursor on the new lane. |
| `c` | On the row of a device: chooses a preset. |
| `ge` | Shows the window of the plugin. |
| `[p` `]p` | Step through the presets. |
| `<Space>dw` | Saves a preset. |
| `<Space>dW` | Makes the preset the default of the device. |
| `dd` | Cuts a device. On a parameter, sets it to its default. |
| `yy` | Copies a device. |
| `p` `P` | Paste a device after or before the cursor, also on a different part. |
| `y` over parameters | Copies their settings. `p` then puts them on the device under the cursor, so `yj` and then `p` on a different synth copies two settings. |
| `gcc` | Bypasses the device. |
| `V` | Selects several devices or parameters, for the keys above. |
| `.` | Repeats the last change. |
| `Alt-j` `Alt-k` | Move the device down or up the chain. |
| `f` | Finds a parameter. |
| `t` | Goes to the last parameter that you changed. |
| `gS` | Chooses the part that the device listens to, as its side-chain. |
| `O` | Chooses where the further output pairs of the device play. |
| `K` | Describes the device or the parameter. |
| `s` | Solos the part. |
| `:device.copy_to <part>` | Copies the selected device to a part. |
| `:device.move_to <part>` | Moves the selected device to a part. |
| `\p`, `:devices.pin` | Pins the devices view to the part that it shows. Again: the view follows the cursor part. `:devices.pin Bass` pins it to the part Bass. |

## Two panels on two parts

The devices view shows in any number of windows, and each window has its own cursor, folds, scroll and part. A view follows the cursor part until you pin it, and a pinned view shows its part wherever the cursor goes. The title of a pinned view says `pinned`. The inspector shows the node of the devices view that had the keys last.

- `:vs devices://Bass` puts a second devices view beside this window, pinned to the part Bass, and a number also names a part, as in `devices://3`.
- `:e devices://Bass` pins the view in this window.
- In a pinned view, the keys and the commands act on its part, so `a` adds a device to that part and `p` pastes there.
- A saved layout and the project keep the part of a pinned view.

## The parts of a row

| Row | Parts, from the left |
| --- | --- |
| Heading of a device | The name. The preset, or a caret when no preset is loaded. At the right: the buttons `⧉` `↑` `↓` `×`, the format, the wet mix, the outputs and the side-chain, and the power chip (`on` or `off`). A device that does not run shows its state in place of the chip. |
| Picture | What a built-in effect does: the curve of the equalizer, the gain reduction, the loudness, the needle of the tuner. |
| Parameter | The name, a slider, the value in its unit, and, when the panel is 36 columns wide or more, `A` (automate) and `L` (learn). |
| Add line | `+ add a device`. |
| Output | The part that this part plays into, and `+ send`. The master has no output row. |
| Send | The part, a slider for the level, the level in dB, `pre` and `×`. |

A parameter that a lane moves shows the value of the lane at the playhead, and in the graphical window its slider is amber and moves while the song plays.

## The pointer

The pointer works in the same way in the terminal and in the graphical window.

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
| `outs`, `key` | A menu of where the further outputs play, or of the part that the device listens to. |
| `offline: o`, `stopped: gR restarts` | Puts the plugin online again, or starts it again. |
| `A`, `L` | Automates the parameter, as the menu does. Learns a MIDI controller for it. |
| `+ add a device` | Opens the picker of devices, as `a` does. |
| The output, `+ send` | A menu of the parts to play into, or to send to. |
| Slider of a send | Sets the level, from -60 dB to +6 dB. A double-click sets 0 dB. |
| `pre`, `×` of a send | Takes the send before the fader. Removes the send. |
