# launcher

The clip launcher: each track has slots, a column of clips that are not on
the timeline. You start and stop these clips while the song plays. A row of
slots across the tracks is a scene. The session view shows the slots and
the scenes, in the terminal and in the graphical window.

```lua
paw.ext.load("extensions/launcher")   -- in init.lua, or `:ext.load launcher` for this session
```

The clips of the slots are clips of the core. The core plays them with a
cue (`paw.api.cue`). So a project with slots opens and plays without the
extension: paw keeps the clips, and plays the timeline.

## Try it

1. Type `:ext.load launcher`, and open a song with a few tracks.
2. Press `<Space>vs`. The session view opens under the arrange view. Each track is
   a column of slots, and the scenes are on the right.
3. Press `o`. The slot under the cursor gets a MIDI clip of one bar. Press
   `i` and enter some notes in the piano roll, then press `<Space>vs` twice to go
   back to the session view.
4. Press `<CR>`. The song starts and the clip loops. The clip is lit, and it
   fills as it goes round its loop. The other tracks play their timelines.
5. Press `S`. The clip stops at the next bar, and the track is silent.
   Press `B`. The track plays its timeline again.

## How to

### How to record a performance into the timeline

1. Press `<Space>vs` to show the session view.
2. To set where launches start, type `:launch.quantize bar`.
3. Press `C` to start a capture.
4. Move to a slot and press `<CR>` to launch it. The song starts with the
   clip.
5. To change parts, launch other slots, or press `L` to launch a full
   scene.
6. To silence a track, press `S`. To play its timeline again, press `B`.
7. Stop the song.

paw writes each clip that played to the timeline as a looped copy. The
parts where a track was silent become empty. One `u` removes the capture.
If you want to render the performance, render after the capture: a render
plays only the timeline.

### How to record a new loop into a slot

1. Select a track with an input, and move to an empty slot.
2. Press `4R` to record four bars from the next boundary.
3. Play. At the end of the four bars, the take becomes the clip of the slot
   and plays immediately.
4. To stop the recording early, press `R` again.

### How to launch slots from pads

1. In the session view, move to a slot.
2. Type `:learn` and press a pad on your controller.
3. To bind a pad to the scene of the row, type `:learn scene` and press the
   pad. `:learn stop` binds a pad that stops the clip of the track, and
   `:learn stop all` a pad that stops every clip.

## Reference

### Launch

- A launch starts the clip at the next boundary of its quantize. The
  default quantize is a bar.
- The clip loops while it plays.
- The clip starts on the same frame as the boundary. The engine times the
  launch, not the Lua runtime.
- A launch while the song is stopped starts the clip immediately, and the
  song starts too.
- While a track plays a slot, the clips on its timeline are silent.
- When you stop the clip, the track stays silent. The track plays its
  timeline again when you send it back (`B`), or when the song stops. A
  stop of the song sends every track back.
- A seek, or a turn of the loop, moves each queued launch to the next
  boundary after the new position. Clips that play keep their position in
  their loop.
- A scene launches every clip in its row on one boundary. A track with no
  clip in that row stops its clip. A track that plays its timeline does not
  change.

### Quantize

| Quantize | A launch waits for |
| --- | --- |
| `off` | nothing |
| `1/16` `1/8` `1/4` | the next sixteenth, eighth or quarter note, counted from the start of the bar |
| `beat` | the next beat of the time signature (an eighth in 6/8) |
| `bar` `2bars` `4bars` | the start of the next bar, or of the next group of two or four bars from the first bar |

The project has one quantize (`:launch.quantize`). A slot can have its own
quantize (`:slot.quantize`).

### Launch modes

The mode of a clip sets how the clip obeys the button of its slot.

| Mode | Effect |
| --- | --- |
| `trigger` | A press launches the clip. If the clip plays, it starts again from its start. |
| `gate` | The clip plays while you hold the button: a pad, or the play mark of the slot. |
| `toggle` | A press launches the clip. A second press stops it. |

A legato clip (`:slot.legato`) starts at the position in its loop where the
clip that it replaces stopped. A clip that is not legato starts at its own
start.

### Keys

`<Space>vs` shows or hides the session view. The keys below are the keys of the
session view. The last row shows what each track plays: a slot, nothing, or
its timeline. A clip that plays is bright and fills as it goes round its
loop. A clip that waits for its boundary has a mark until it starts.

| Keys | Effect |
| --- | --- |
| `h` `l`, `<Left>` `<Right>` | the previous track, the next track |
| `j` `k`, `<Down>` `<Up>` | the next slot, the previous slot |
| `gg` `G` | the first slot, the last slot with a clip (with a count: slot N) |
| `0` `^` `$` | the first track, the last track |
| `<CR>` | launch the slot (on an empty slot: stop the track) |
| `L` | launch the scene of the row at the cursor |
| `S` `gS` | stop the clip of the track, stop every clip |
| `s` `M` `r` | solo the track, mute the track, arm the track (as in every view) |
| `B` `gB` | send the track back to its timeline, send every track back |
| `o` | make a MIDI clip of one bar in the slot (`:slot.new 2` for two bars) |
| `i` | open the notes of the clip in the piano roll |
| `x` `dd` | empty the slot |
| `yy` | copy the clip of the slot into a register |
| `p` | paste a clip into the slot: a clip copied here, or the first clip copied in the arrange view |
| `gp` | copy the clip under the cursor of the arrange view into the slot |
| `~` | the next launch mode |
| `g~` | legato on or off |
| `R` `4R` | record one bar, or four bars, into the empty slot. Again: stop. |
| `grn` | give a name to the scene |
| `C` | capture the launches into the timeline, on or off |

With `paw.opt.keys = "classic"`, `s` `S` stop, `b` `B` send back and `e`
opens the notes, as before the key rule.

### The pointer

In the terminal and in the graphical window, the session view takes the
same gestures. In the window, it is in More ▸ Session.

| Gesture | Effect |
| --- | --- |
| Press the play mark at the left of a slot | Launch the clip, or stop the track on an empty slot. Release stops a gate clip. |
| Click a slot | Select the slot. |
| Double click a slot | Open its notes in the piano roll. On an empty slot, make a MIDI clip of one bar first. |
| Drag a clip to another slot | Move the clip. With Ctrl: copy it. |
| Drag a clip from the timeline to a slot | Copy the clip into the slot (in the graphical window). |
| Click the dot of an empty slot | Record into the slot. |
| Right click a clip | The menu of the clip. |
| Click the name of a scene | Launch the scene. |
| Click the last row | Stop the clip of the track. Under the scenes: stop every clip. |
| The wheel | Scroll the rows. With Shift: the tracks. |

### Record into a slot

`R` on an empty slot (`:slot.record`) records into it. The recording starts
at the next boundary of the quantize of the project. It lasts one bar, or
the number of bars of the count (`4R`, `:slot.record 4`).

- If the track is not armed, paw arms it. The track is silent from the
  boundary while it records.
- The take uses the usual recording, through the input of the track.
- At the end, the part of the take between the two boundaries becomes the
  clip of the slot. The take does not stay on the timeline.
- The clip then plays immediately, in time, as if it started at the bar
  where the recording started.
- `R` again, or a stop of the song, ends the recording early. paw keeps
  what it recorded.
- Punch recording and the pre-roll do not apply while a slot records. A
  count-in plays if the song was stopped. A launch while the song is
  stopped plays immediately, without either.

### Capture

A render plays the timeline: a render does not include the launched clips.
When capture is on (`C`, `:launch.capture`), a stop of the song writes the
performance to the timeline:

- Each part of the song where a track played a slot becomes a looped copy
  of that clip on the timeline of the track. The copy goes from the
  boundary where the clip started to the boundary where it stopped.
- Each part where the track was stopped becomes empty on its timeline.
- The capture is one undo step.

### Commands

| Command | Effect |
| --- | --- |
| `:session` | show the session view and go to it |
| `:launch`, `:launch 2` | launch the slot at the cursor, or the slot in row 2, of the selected track |
| `:launch.stop`, `:launch.stop all` | stop the clip of the track, stop every clip |
| `:launch.back`, `:launch.back all` | send the track back to its timeline, send every track back |
| `:launch.quantize 1/8` | set the quantize of the project (alone: say it) |
| `:launch.capture` | start a capture, or stop it |
| `:scene`, `:scene 2` | launch the scene at the cursor, or scene 2 |
| `:scene.name Chorus` | give a name to the scene at the cursor |
| `:slot.new`, `:slot.new 2` | make a MIDI clip of one bar, or two bars, in the slot |
| `:slot.copy` | copy the clip under the cursor of the arrange view into the slot |
| `:slot.delete` | empty the slot |
| `:slot.edit` | open the notes of the clip in the piano roll |
| `:slot.record 2` | record two bars into the empty slot from the next boundary |
| `:slot.mode gate` | set the launch mode (alone: the next mode) |
| `:slot.legato` | legato on or off |
| `:slot.quantize 1/16` | set the quantize of the slot (alone: use the quantize of the project) |
| `:slot.length 2` | set the number of bars that the clip loops over |

### Controllers

The extension adds three buttons to `:learn` (see the MIDI controllers page
of the manual, `:help learn`):

| Target | A pad or a button |
| --- | --- |
| `launch` | launches a slot of a track: `:learn launch`, or `:learn` in the session view |
| `scene` | launches the scene of a row: `:learn scene` |
| `stop` | stops the clip of a track (`:learn stop`), or every clip (`:learn stop all`) |

### Options

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.launch_rows` | `8` | The minimum number of rows in the session view. |

### Data

The clips of the slots are clips off the timeline of the core
(`paw.api.cue_list`). The extension keeps its own data in `meta`:

| Where | What |
| --- | --- |
| `clip.meta.launcher` | `row` (from 0), and `quantize`, `mode` and `legato` when they are not the default |
| `project.meta.launcher` | `quantize` (when it is not `bar`) and `scenes`, the names of the scenes by row |

The export to REAPER and to DAWproject does not write the clips of the
slots: the report of the export counts them.

### Lua

In Lua, rows start at 0. On the screen and in commands, rows start at 1.

```lua
local launcher = require("launcher")
local id = launcher.add(track.id, 0, { length = 8, notes = { ... } })   -- as paw.api.clip_add takes them
launcher.set(id, "mode", "gate")               -- also "quantize", "legato"
launcher.move(id, other.id, 2)                 -- to another slot
launcher.copy(clip.id, track.id, 1)            -- a copy of a clip in a slot
launcher.slots(track.id)                       -- { [row] = clip }, each with slot, mode, quantize, legato

launcher.launch(track.id, 0)                   -- or press(track, row) / release(track, row), by its mode
launcher.scene(1)
launcher.stop(track.id)                        -- with no track, every clip
launcher.back()                                -- every track back to its timeline
launcher.state()                               -- by track: slot or stopped, phase, length, since, queued, at
launcher.set_quantize("1/8")
launcher.set_scene_name(1, "Chorus")
launcher.capture(true)
```

## About the launcher

Some music does not start with a fixed order. You find a song when you try
parts against each other, and you play some songs live in a different order
each time. Ableton Live has a session view for this, and the launcher
copies the idea.

The launcher is an extension because not all users play live. The core
gives two parts that must be in the core. The first is clips that are not
on the timeline. The second is a cue that the engine times to the frame.
The launcher adds
the grid of slots, the scenes, the modes and the view. For why the engine
times a cue, and why a render plays only the timeline, see
`:help about-cues`.

## What it does not do

- No follow actions (a clip that launches the next clip, or a random
  clip).
- Under a tempo ramp, a clip in a slot spreads the beats of each block
  evenly over its frames, at the tempo the block starts with.
