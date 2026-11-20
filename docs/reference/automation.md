# Automation

<!-- tags: automation automation-modes lane-write -->

Automation lanes move a fader, a pan or a parameter while the song plays.
This page describes the automation modes, which write lanes when you move
a control. For the keys that draw and edit lanes, see
[Keys, by idea](keys.md). For the steps, see
[How to write automation with the faders](../how-to/write-automation-with-the-faders.md).

## Automation modes

Each track has an automation mode: `track.automation`.

| Mode | While the song plays |
| --- | --- |
| `read` | Default. The lanes play. A move of a control writes nothing. |
| `touch` | A control writes while you hold or move it. When you release it, the lane controls it again, and the written part joins the lane. |
| `latch` | A control writes from its first move until the song stops. |
| `write` | Each lane of the track is written from where the song starts to play, with or without a move. |
| `off` | The lanes stay but do not play. The fader, the pan and the parameters stay where you set them. |

| Keys, command | Effect |
| --- | --- |
| `:automation touch` | Set the mode of the track. |
| `:automation read all` | Set the mode of every track. |
| `:automation`, `,am` | The next mode. |
| `:lane.write`, `,aw` | Write on, for the full song. Again: off. `:lane.write off`: off. |
| `,al` | Select what to automate, and show its lane. |

In the graphical window, the `A` flag on the track header shows the mode.

## Rules

- A control is a fader, a pan or a parameter. A move can come from the
  keyboard, a frontend, a MIDI controller or the editor of a plugin.
- paw writes into the lane at the playhead, over what the lane had there.
  If there is no lane, paw makes one.
- In the graphical window, a control is held while the pointer holds it
  (`paw.api.automation_hold`). Any other control counts as held for a
  little more than half a second after its last move.
- While `:lane.write` is on, each track that does not write in its own
  mode latches.
- The track header in the terminal shows `T`, `L` or `W` in red while a
  track writes, and `-` when its automation is off.

## State lanes

A state lane gives a device one of a few states at each point. The device
keeps the state up to the next point. Before the first point, the first
state holds. A state lane has no curve between two points. For why some changes
land on the frame of the point and some after it, see
[About state lanes](../explanation/about-state-lanes.md).

Each state has a `name` and one or more of these fields:

| Field | Value | Where the change lands |
| --- | --- | --- |
| `params` | parameter values by key | on the frame of the point |
| `program`, `bank` | a program change (0 to 127) and its bank (0 to 16383), for this device only | on the frame of the point |
| `call` | `{ method, data }`: a request, as `paw.api.device_call` makes it. An LV2 `property.set` becomes a message on the audio thread | on the frame of the point. As the song plays, a file that the plugin loads in the background plays some milliseconds later |
| `state` | the whole saved state of the plugin, in base64 | in a rendered file, on the frame of the point. As the song plays, when the main loop sees the playhead after the point |

| Keys, command | Effect |
| --- | --- |
| `,al`, then `state` | Make the state lane of a device of the track, and show its row. |
| `\s` on the lane's row, `:lane.state [name]` | Keep the device's state now (its saved state and its parameters) as a state of the lane, and give it from the cursor. The default name is the name of the device's preset, or the next free letter. |
| `c` on the lane's row | Choose the state of the point under the cursor, or of a new point there, from a list. |
| `+` `-` | Give the point under the cursor the next or the previous state. |
| `A`, `x`, `w`, `b` | Add a point with the state at the cursor, remove a point, go to the next or the previous point, as on each lane. |

The row shows the name of each point's state, up to the next point.

### Rules

- A device has at most one state lane.
- A rendered file waits for a plugin to be ready at its start and after
  each saved state: until the process of the plugin uses no processor
  time for a moment, at most `settle` seconds (default 5, a field of the
  render). A plugin in paw's own process gives no sign, so the render
  waits half a second after a saved state.
- A render gives each lane's state at its start before the first frame.
  With plugins, it then plays half a second of silence with the song
  stopped, so that a plugin can finish a fade to a new model.
- While a state lane drives a device, the project keeps the device's own
  state, and does not read the lane's state back. When the lane stops or
  goes, the device gets its own state and parameters again.
- An instrument can stop its notes when it gets a saved state. Put the
  point a little before the notes that need the new state.
- The `plugstate` extension makes states from models, presets, scenes and
  snapshots: see `:plugstate.at` in its
  [README](../../extensions/plugstate/README.md).

### Lua

| Function | Effect |
| --- | --- |
| `device:automate_state()` | The state lane of the device, made if there is none. |
| `device:state_lane()` | The state lane of the device, or nil. |
| `device:capture(name)` | The state of the device now, as a lane takes it. |
| `lane:add_state(state)` | Add a state, or replace the state with its name. Returns its index, from 0. |
| `lane:set_state(beat, name)` | A point that gives the state from `beat` on. |
| `lane:states()` | The states of the lane. |
| `paw.api.lane_add(track, { target = "state", device = id, states = {...} })` | Make a state lane. |

## Undo of a control move

A fader that you drag in the graphical window, or a knob on a controller,
sets its value many times each second. paw makes the moves of one control
that come less than one second apart into one undo step. So one undo
removes the full sweep. Each command and each key is one step.
