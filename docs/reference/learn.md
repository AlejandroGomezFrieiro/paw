# MIDI controllers

<!-- tags: learn midi-controllers -->

A knob, a fader or a wheel of a MIDI controller can move a control, which is the fader or the pan of a track, or a parameter of a device. A pad or a button can press a button that an extension adds, and with the [clip launcher](../../extensions/launcher/README.md) a pad can launch a slot or a scene, or stop clips. The Lua module is `paw.learn`.

## Commands

| Command | Effect |
| --- | --- |
| `:learn` | Wait for a controller, then bind it. The target is the parameter at the cursor of the device panel, the fader at the cursor of the mixer, or the slot at the cursor of the session view (clip launcher). Else the target is the last control that moved. |
| `:learn volume`, `:learn pan`, `:learn cutoff` | Bind the fader, the pan, or a parameter (by key or name) of the selected track. |
| `:learn launch` | Bind a pad that launches the slot at the cursor of the session view (clip launcher). |
| `:learn scene` | Bind a pad that launches the scene of the row at the cursor of the session view (clip launcher). |
| `:learn stop`, `:learn stop all` | Bind a button that stops the clip of the selected track, or every clip (clip launcher). |
| `:learn.cancel` | Stop the wait for a controller. |
| `:learn.param 12 cutoff` | Bind a parameter of a device, by the device id and the parameter key. The frontends use it in their menus. |
| `:learn.list` | Show the bindings in a list. Select one to remove it. |
| `:learn.remove 2`, `:learn.remove volume` | Remove a binding, by its number in `:learn.list` or by its target. |
| `:learn.clear` | Remove every binding. |

`:param.last learn` binds the parameter that moved last (see
[Plugins](plugins.md)).

## Graphical window

- The plug icon next to a parameter of a device binds that parameter.
- The menu of a track has the fader and the pan.

## Behavior

- The bindings are part of the project (`project.meta.learn`), so the project saves them and undo changes them.
- A move from a controller works like any other move of a control, and it writes automation when the automation mode of the track says so (see [Automation](automation.md)). One sweep is one undo step.
- Pickup means that a control moves its target only after the control reaches the value of the target, so the target does not jump to the value of the control. Set `paw.opt.learn_pickup = false` to let the target jump.
- A binding uses the controller number (or the note) and the channel. paw does not compare the port that the message came from.
- A pad that sends notes binds by its note. A pad that sends a controller counts as pressed when the value goes above the middle of its range, and a gate clip stops when you release the pad.

## Lua

```lua
paw.learn.bind({ cc = 74, channel = 1 }, { track = t.id, target = "param", device = d.id, param = "cutoff" })
paw.learn.bind({ note = 36, channel = 10 }, { track = drums.id, target = "launch", slot = 0 })
paw.learn.bind({ cc = 20 }, { target = "scene", slot = 1 })
paw.learn.bind({ note = 48 }, { target = "stop" })          -- every clip
```

| Function | Effect |
| --- | --- |
| `paw.learn.bind(source, target)` | Bind a source (`cc` or `note`, and `channel`) to a target. |
| `paw.learn.bindings()` | The list of bindings. |
| `paw.learn.unbind(which)` | Remove a binding, by number or by target. |
| `paw.learn.clear()` | Remove every binding. |
| `paw.learn.start(target)` | Wait for a controller for this target. |
| `paw.learn.trigger(name, spec)` | Add a kind of button target: `press(binding, down)`, `name(target)`, and optionally `check`, `words`, `target_for(word, track)` and `under_cursor(view)`. |

A target is a table with `track` and `target` (`"volume"`, `"pan"`, `"param"`, or a button that an extension adds), and it also has `device` and `param` when it names a parameter. A button can keep a number in `slot`, and the clip launcher keeps the row (counted from 0) of a launch or a scene there. A binding to a button of an extension that is not loaded stays in the project and does nothing.
