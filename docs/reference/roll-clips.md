# Several clips in the piano roll

<!-- tags: roll-clips context-notes -->

The piano roll can show the notes of other tracks and edit many clips
at the same time, and the module that does so is `paw.roll_clips`.

## Context notes

Behind the notes of the clip, the piano roll shows the notes of other
tracks that sound at the same time, drawn fainter and each in the color of
its track.

- Drum tracks (tracks with a drum map, see `extensions/drums`) do not
  appear as context notes.
- `paw.opt.roll_context` sets which tracks show: `"all"` (default),
  `"group"` (the tracks of the group of the clip), `"none"`, or a list of
  track ids.
- `:roll.tracks` (terminal) or the side panel (graphical window, Tracks in
  the toolbar) shows or hides each track.
- The piano roll shows at most `paw.opt.roll_context_max` notes (4000).
  paw finds them again only when those notes, the edited clips or the
  shown tracks change. When you edit the notes of the clip, the notes
  behind them stay as they are.
- The keyboard marks the keys that sound at the cursor, in each clip that
  shows. If `paw.harmony` is there, paw shows the name of their chord.
  Right after an edit, the name can be the one from before the edit,
  until paw reads the chords again.

## Edit several clips

The piano roll edits one active clip, where new notes go, and any number
of other clips with it, and each action on notes works on all of them, as in the list below.

- motions (`w` goes from note to note across the clips)
- operators and text objects (`d`, `y`, `>`, `=`, and `ic`, which is each
  note of each clip)
- visual mode, `p`, and the keys on the note under the cursor
- the clicks, boxes and drags of the pointer, and the velocity strip
- quantize, and the operators of musicops (each clip separately).

Rules:

- A note stays in its clip, so a drag or `H` stops at the edges of the clip,
  and a move never puts a note in a different clip.
- Notes copied from several clips remember their clips, and a paste puts them
  back in their clips while those clips are edited. Otherwise they go into the
  clip at the cursor.
- A command that changes several clips is one undo step.
- The beats of the cursor are the beats of the active clip, and when a
  different clip becomes active, the cursor stays at the same place in the
  song.

| Action | Terminal | Graphical window |
| --- | --- | --- |
| Make the clip of a context note active | `ga` on the note | click the note |
| Edit the clip of a note too, or stop | `gE` on the note | Ctrl and a click, or the box in the side panel |
| Make the next or previous edited clip active | `gn` `gN` | a click on its name in the side panel |
| Edit the next or previous shown track (its clip at the cursor) | `]t` `[t`, or `Tab` `Shift-Tab` to go round | click one of its notes |
| Open several clips | select them in the arrange view, `Enter` | select them, double click one |
| Edit one clip again | `:roll.only`, or open a clip | open a clip |

## Lua: `paw.roll_clips`

| Function | Result |
| --- | --- |
| `paw.roll_clips.ids()` | The ids of the edited clips. |
| `paw.roll_clips.active()` | The id of the active clip. |
| `paw.roll_clips.editable(id)` | True if the clip is edited. |
| `paw.roll_clips.parts()` | `{ id, clip, offset, start, length, track, name }` for each edited clip, the active clip first. `offset` is the number of beats after the active clip where it starts. |
| `paw.roll_clips.span()` | The range that the clips cover, in the beats of the roll. |
| `paw.roll_clips.open(ids, active)` | Edit these clips. |
| `paw.roll_clips.only()` | Edit the active clip only. |
| `paw.roll_clips.activate(id)` | Make a clip active. |
| `paw.roll_clips.toggle(id)` | Edit a clip too, or stop. |
| `paw.roll_clips.cycle(n)` | Make the clip `n` places away active. |
| `paw.roll_clips.visible()` | The tracks that the roll shows, in the order of the track list. |
| `paw.roll_clips.step_track(n, wrap)` | Edit the track `n` places away (`]t`, `[t`, `Tab`). |
| `paw.roll_clips.notes(range)` | The notes of each edited clip, in the beats of the roll. Each note has `clip` and `place` (its position in its clip, for `Clip:edit_notes`). |
| `paw.roll_clips.note_at(pitch, beat)` | The note at a pitch and beat. |
| `paw.roll_clips.tracks()`, `paw.roll_clips.show_track(id, on)` | The tracks near the roll; show or hide one. |
| `paw.roll_clips.context()` | The context notes: `{ pitch, start, length, velocity, clip, track, color }`. |
| `paw.roll_clips.context_at(pitch, beat)` | The context note at a pitch and beat. |
| `paw.roll_clips.sounding(beat)` | The pitches that sound at a beat, and the name of their chord. |
| `paw.roll_clips.rows()`, `paw.roll_clips.pick()` | The rows of the side panel; the list of `:roll.tracks`. |

- The event `roll_clips.changed` comes when the set of clips or the active
  clip changes.
- `paw.edit.roll.yank`, `delete`, `each` and `paste` accept the list from
  `parts()` instead of a clip.
- Each seat has its own set, so two people on one kernel edit their own
  clips.
- Language servers keep each edited clip open, and not only the active clip.

## Layers of the piano roll

The piano roll draws the layers below, from back to front.

| Layer | Order |
| --- | --- |
| the grid | |
| `context`: the notes of other tracks | 10 |
| `notes`: the notes of the clips | 20 |
| diagnostics | 30 |
| the marks of a snippet | 40 |
| suggestions | 50 |
| the selection and the cursor | |

`paw.ui.views.pianoroll.layer(name, order, paint, marks)` adds a layer.

- `paint(p)` draws the layer in the cells of the terminal. `p` has `roll`,
  `ruler`, `clip`, `parts`, `x(beat)`, `row(pitch)`, `from`, `to`, `zoom`,
  `top`, `rows`, `width` and `hue`.
- `marks(clip_id)` gives what the graphical window draws for the layer:
  boxes or chips in the beats of the clip. Layers with an order below 20
  are behind the notes, and layers with an order of 20 or more are in front.
- The comment on `layer` in `runtime/lua/paw/views/pianoroll.lua` gives
  each field. The `context` layer is an example of both functions.
