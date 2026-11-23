# Frozen tracks

<!-- tags: freezing frozen freeze -->

A frozen track plays a rendered file instead of its clips and devices. The devices rest, so a heavy instrument costs nothing while it is frozen. A block of a subproject can be frozen too. The modules are `paw.freeze` and `paw.freeze_block`, and the steps are in [How to freeze a heavy track](../how-to/freeze-a-heavy-track.md).

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
- The `meta` of the track keeps the freeze (`frozen = { file, key }`), so a freeze is one undo step, and the project saves it. The `key` records what the file was made from.
- `K` on a frozen track says if the file is up to date, or stale with the reason, for example `frozen, stale: Drums changed since: devices`. On a track inside a frozen group, it says `held in Strings, which is frozen` and the same state.
- The reason names each part that changed since the freeze. The parts are `clips`, `devices`, `automation`, `mix` (the fader, pan, mute and output of a track inside a frozen group) and `tempo`. The fader, pan and mute of the frozen track itself are not a part, because they stay live.
- An undo that puts a part back as it was makes the file up to date again. The key does not hold the saved state of a plugin, only its parameters, so a change inside the window of a plugin that moves no parameter does not make the file stale.
- The file goes to the `media` folder of the project, and the project names it relative to itself, in the same way as recordings.
- A freeze does not change the clips, notes and devices. If you edit them on a frozen track, paw asks one time if it must unfreeze the track. paw keeps the edit in both cases, and you hear it when the track is not frozen.
- A render of the song plays the frozen file, and it sounds as before the freeze. The suite compares them sample by sample.
- A change of tempo does not render the file again, so `K` says the file is stale. To render it again, unfreeze and freeze.
- The vocal freeze of `extensions/utau` is a different function, because it waits for the voice synthesis.

## Frozen blocks of subprojects

`:freeze` and `:unfreeze` with the cursor on a block of a subproject freeze the block, and not the track. See [Subprojects](subprojects.md#freeze-a-block) for the commands.

- The file holds what the block plays into its return row: the tracks of the subproject and its master, with their devices and faders, and the subprojects inside it. The devices, fader, lanes and sends of the return row stay live.
- The return row plays the file in place of the block. While no block of the subproject plays it live, its tracks are held, so its devices rest.
- Only a block of the song can be frozen. A block inside another subproject cannot. A block that plays one track of the subproject with no devices or fader of its own plays its notes through the devices of its row, so freeze the row instead.
- The file goes to `media/baked` in the project, and its name comes from the key of what it was made from. Two blocks that play the same part of a subproject at places with the same tempo have the same key, so they share one file.
- The `meta` of the block keeps the freeze (`frozen = { file, key, length, tail }`), so a freeze is one undo step, and the project saves it. `length` is the beats of the file, with the tail.
- The key has the same parts as the key of a frozen track. The `clips` part also holds where the block starts in the subproject and how long it is. The `tempo` part holds the tempo and meter from the start of the block to the end of its tail, and the own tempo of the subproject, if it has one.
- `K` on a frozen block says `frozen, up to date`, or `frozen, stale` with the parts that changed. The status line names each subproject with a stale frozen block, for example `stale: Ballad`. `:freeze` on a stale block renders it again.
- An edit inside the subproject does not ask to unfreeze the block. You hear the edit after `:unfreeze`, or after `:freeze` renders the block again.

## Lua

| Function | Result |
| --- | --- |
| `paw.freeze.freeze(track, { tail = 2 })` | Freeze a track or a group. |
| `paw.freeze.unfreeze(track)` | Unfreeze it. |
| `paw.freeze.state(track)` | `"frozen"`, `"held"` or nil. |
| `paw.freeze.describe(track)` | What `K` says of the freeze: `"frozen, up to date"`, `"frozen, stale: Drums changed since: devices"`, or nil for a track that plays live. |
| the `freeze` option of a render | `paw.render(path, { freeze = id })` renders what a freeze of `id` renders. |
| `paw.freeze_block.freeze(clip, { tail = 2 })` | Freeze the block with the clip id `clip`, or render a stale one again. Returns the file. |
| `paw.freeze_block.unfreeze(clip)` | Unfreeze it. |
| `paw.freeze_block.frozen(clip)` | `{ file, key, length, tail }`, or nil for a block that plays live. |
| `paw.freeze_block.describe(clip)` | What `K` says of the freeze: `"frozen, up to date"`, `"frozen, stale: Ballad changed since: clips"`, or nil. |
| the `block` option of a render | `paw.render(path, { block = clip })` renders what a freeze of the block renders. |

The core part is `crates/paw-core/src/freeze.rs`.
