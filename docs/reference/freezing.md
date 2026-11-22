# Frozen tracks

<!-- tags: freezing frozen freeze -->

A frozen track plays a rendered file instead of its clips and devices. The devices rest, so a heavy instrument costs nothing while it is frozen. The module is `paw.freeze`, and the steps are in [How to freeze a heavy track](../how-to/freeze-a-heavy-track.md).

## Commands

| Command | Effect |
| --- | --- |
| `:freeze` | Freeze the track at the cursor, or a group with all its tracks. |
| `:freeze Strings` | Freeze a track or a group by name. |
| `:t2,t4freeze` | Freeze a range of tracks. |
| `:freeze tail=4` | Render 4 seconds after the end (default: 2). |
| `:unfreeze` | Play the clips and devices again. On a track inside a frozen group, unfreeze the group. |

## Rules

- The freeze is taken before the fader. The fader, pan, mute and sends stay live, so you can continue to mix a frozen track. To render the fader too, use `:track.bounce` (see [Render](render.md#bounce)).
- The tracks inside a frozen group are held, which means they are silent with their devices at rest, because the file of the group holds their sound. A send from one of them to a track outside the group is not heard while the group is frozen.
- The arrange view marks the header of a frozen track `F`, and each held track `f`.
- The `meta` of the track keeps the freeze (`frozen = { file }`), so a freeze is one undo step, and the project saves it.
- The file goes to the `media` folder of the project, and the project names it relative to itself, in the same way as recordings.
- A freeze does not change the clips, notes and devices. If you edit them on a frozen track, paw asks one time if it must unfreeze the track. paw keeps the edit in both cases, and you hear it when the track is not frozen.
- A render of the song plays the frozen file, and it sounds as before the freeze. The suite compares them sample by sample.
- A change of tempo does not render the file again, so unfreeze and freeze.
- The vocal freeze of `extensions/utau` is a different function, because it waits for the voice synthesis.

## Lua

| Function | Result |
| --- | --- |
| `paw.freeze.freeze(track, { tail = 2 })` | Freeze a track or a group. |
| `paw.freeze.unfreeze(track)` | Unfreeze it. |
| `paw.freeze.state(track)` | `"frozen"`, `"held"` or nil. |
| the `freeze` option of a render | `paw.render(path, { freeze = id })` renders what a freeze of `id` renders. |

The core part is `crates/paw-core/src/freeze.rs`.
