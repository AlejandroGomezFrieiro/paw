# Project objects in Lua

This page describes the Lua objects of the project, which are tracks, devices, clips, notes, note attributes, the transport, the tempo map and automation. Units are in [The Lua interface](scripting.md#units).

## Objects are handles

An object is a handle, so when you read a field, Lua asks the kernel, and when you write a field, Lua tells the kernel.

```lua
paw.project.tempo = 112
local bass = paw.add_track({ name = "Bass", volume = -4 })
local synth = bass:add_device("synth", { wave = 2, cutoff = 500 })
synth:set("resonance", 0.3)
synth.bypass = false

local clip = bass:add_clip({ start = 0, length = 4 })
clip:add_note({ pitch = "A1", start = 0, length = 0.5, velocity = 100 })
clip:add_notes({ { pitch = 45, start = 1 }, { pitch = 48, start = 2 } })
-- An audio clip from a WAV, AIFF, FLAC, MP3 or Ogg Vorbis file.
local take = bass:add_clip({ start = 8, file = "take.flac" })
take:peaks(64)                 -- 64 { min, max } pairs, to draw the waveform

local bus, echo = paw.add_track({ name = "Bus" }), paw.add_track({ name = "Echo" })
bass.output = bus              -- the output goes into another track
bass:send(echo, -12)           -- a send to a third track, 12 dB down

paw.tracks()   bass:devices()   bass:clips()   clip:notes()   bass:clip_at(2)
paw.project.save("song")   paw.project.load("song")
paw.render("mix.wav", { tail = 2 })
```

`paw.device_types()` lists every kind of device, with its format and vendor.
`track:snapshot()` and `paw.restore_track(snapshot, index)` copy a track
with its devices, clips and automation.

## Notes

A note has a place among the notes of its clip, and the notes of a clip are in the order that they start. These functions edit one note at a time.

```lua
local note, at = clip:note_at("E2", 1.25)       -- the note that sounds there, and its place
clip:set_note(at, { length = 2 })               -- returns the new place of the note
clip:add_note({ pitch = "G2", start = 3, length = 1 })
clip:remove_note(1)
clip:notes({ from = 0, to = 4, low = "C2", high = "C3" })   -- some of the notes, with their places
clip:edit_notes({ set = { { index = 1, start = 0.5 } }, remove = { 2 }, add = {} })  -- one edit
```

A note also has an id, `note.id`, and the id stays with the note through every edit.

### `meta` for the data of an extension

`note.meta` and `clip.meta` are tables for data that MIDI cannot hold, e.g., a lyric or the letter name of a pitch. Each extension writes under a key of its own (`meta.lyric`, `meta.notation`). The core keeps `meta` with the note through moves, copies, undo and project files, and it does not read the contents.

```lua
clip:add_note({ pitch = 60, start = 0, meta = { lyric = "la" } })
```

The project saves `project.meta` and `track.meta` too. See [About MIDI as the truth](../explanation/about-midi-as-the-truth.md).

## MIDI files

`paw.midifile.read` gives the contents of a file in ticks, with `ppq` ticks to a beat, in the form `{ format, ppq, tracks = { { name, notes, controls } }, tempos, signatures, markers, skipped }`.

```lua
paw.open("song.mid")                                            -- a new project, as :open does
paw.midifile.import("song.mid", { start = 16, tempo = true })   -- into this project; { track = t } makes one clip
paw.midifile.export("out.mid", { clips = { clip.id } })         -- or { tracks = { ... } }, or all the project
local file = paw.midifile.read("song.mid")                      -- parse(bytes) and encode(file) use bytes
```

## Note attributes: `note.attr`

`note.attr = { type, data }` is the attribute of a MIDI 2.0 note-on, or nil. It is usually an articulation of the orchestral articulation profile (M2-123), and then `type` is the classification (0x10 to 0x1F) and the top bits of `data` are the subclass and the variation.

The attribute is MIDI, and the core keeps it through edits, copies, undo, project files and recordings from MIDI 2.0 input. In a MIDI file, it is a sequencer-specific event immediately before the note, and other programs ignore that event.

The attribute goes to MIDI 2.0 ports, to CLAP plugins that prefer MIDI 2.0 notes, and to devices in Lua. MIDI 1.0 destinations do not get it, but a `track.attr_map` can send it to them as keyswitches.

```lua
clip:add_note({ pitch = "G4", start = 2, attr = paw.attr.m2("11.A") })   -- pizzicato
clip:set_note(at, { attr = false })            -- removes it. Without `attr`, a change keeps it
paw.attr.m2("11.A")          -- { type = 0x11, data = 0xA000 }. "10.23" has a variation
paw.attr.m2(note.attr)       -- "11.A", or nil when it is not an articulation
paw.attr.m2("11.A", { direction = "up", string = 4, reset = true })
paw.attr.parts(note.attr)    -- { type, data, subclass, variation, direction, reset, string }
paw.attr.describe(note.attr) -- { code = "11.A", tag = "pz", name = "Pizzicato", class = ..., text = "Pizzicato (11.A)" }
bass:play_note("C2", 100, 200, paw.attr.m2("11.0"))   -- live, after the events of the map
```

The piano roll writes the tag on a note when the note is long enough, the graphical window gives the note a chip, and `K` shows the articulation. The core keeps only the numbers, and the [articulations extension](../../extensions/articulations/README.md) gives them names for each instrument.

## `track.attr_map`

The map of a track changes the attributes of its notes into events for an instrument that takes only MIDI 1.0. The map is plain data, so the project keeps it and plays it with no extension loaded.

```lua
track.attr_map = {
  send = "change",                   -- "change": only when the articulation changes. "every": each note
  default = { out = "ks=C1" },       -- notes with no attribute. Or the code of an entry: default = "10.0"
  arts = { ["11.0"] = { out = "ks=D1" }, ["11.A"] = { out = "ks=E1 cc1=96", name = "pizz" } },
  by_type = { [0x13] = { out = "pc=12" } },   -- a full classification, or another type of attribute
  chase = { 1, 11 },                 -- controllers that paw sends again after a change
  attribute = true,                  -- notes keep their attribute. false removes it. `attr` keeps it for one entry
  delay = 0,                         -- milliseconds, for each note whose entry has no `delay`
}
track.attr_map = nil                 -- no map
```

`out` is a list of events with spaces between them, and the table below names the events.

| Event | What it sends |
| --- | --- |
| `ks=D1` | a keyswitch. `ks=D1:64` has a velocity |
| `hold=D1` | a key held while the articulation continues |
| `cc32=40` | a controller value, 0 to 127 |
| `pc=12`, `pc=12/258` | a program change, with a bank |
| `bend=0.5` | a pitch bend |
| `ch=2` | the note and its events go on channel 2 (for a multi-timbral instrument) |
| `attr` | the note keeps its attribute |

Key names have C4 as 60. An entry may hold other fields beside `out`, and paw keeps them without reading them.

paw finds the entry of a note by its code. If there is no entry, paw tries the following, in this order, as M2-123 says:

1. The subclass without its variation.
2. The `by_type` entry of the classification.
3. The subclass 0 of the classification.
4. `"10.0"`.
5. `default`.

The events go on the beat of the note, before the note, because a keyswitched sampler needs this order. When playback starts, or the loop starts again, paw sends the last change before that point first. paw refuses a map that it cannot read.

### Delays

An entry with `delay` moves its notes by that number of milliseconds, and a negative value moves them earlier.

```lua
arts["11.0"] = { out = "ks=D1", delay = -80 }
```

paw moves the start, the end and the keyswitch of each note 80 ms earlier, and `attr_map.delay` applies to each note whose entry has no `delay`.

- The kernel moves the notes when it schedules the events of the track, and it uses the tempo map at each note. Playback, an offline render, a bounce and a freeze give the same result, and a tempo change moves the notes again.
- A note that moves before the start of playback (the first beat, a seek, the start of the loop) starts at the start of playback.
- Notes played live do not move.
- `paw.attr.delay_of(track, attr)` gives the delay of a note, for a view.

## Transport

```lua
paw.transport.play()   paw.transport.stop()   paw.transport.seek(8)
paw.transport.loop_start, paw.transport.loop_end = 0, 16
paw.transport.loop_enabled = true
bass:play_note("C2", 100, 200)     -- play a note now, outside the timeline
paw.transport.record()             -- record the armed tracks
paw.transport.punch_start, paw.transport.punch_end = 16, 32   -- record only there
paw.transport.punch_enabled = true
paw.opt.count_in = 1               -- one bar before a take. transport.counting is the time that is left
paw.opt.pre_roll = 2               -- play two bars, and paw.opt.pre_roll_seconds more, before a punch-in
```

## Tempo

`paw.tempo` reads and sets the tempo map with `at(beat)`, `set(beat, bpm)`, `remove(beat)`, `points()`, `signatures()` and `set_signature(bar, num, den)`.

`paw.tempolane` is the row under the ruler that shows the tempo map.

| Function | Effect |
| --- | --- |
| `show(on)`, `toggle()`, `shown()` | show or hide the row |
| `range()` | the tempo at the bottom and at the top of the row |
| `add(beat, bpm)` | add a point |
| `move(beat, to, bpm)` | move a point |
| `remove(beat)` | remove a point |
| `ramp(beat, on)` | make the tempo glide from a point to the next point, or stop it. Without `on`, it toggles |
| `draw(points, step)` | write the points of a line drawn with the pointer, `step` beats apart |

Each edit goes through `paw.tempo` and is one undo step.

## Automation

An automation lane moves the volume or the pan of a track, or one parameter of a device on the track. A lane is a list of points `{ beat, value }` in the units of its target, which are dB, -1 to 1, or the range of the parameter. Straight lines join the points, and the value does not change before the first point or after the last point.

```lua
local fade = bass:automate("volume")            -- or "pan". It gives the lane that exists, if there is one
fade:add(0, -60)   fade:add(8, 0)               -- a point replaces the point at the same beat
synth:automate("cutoff"):set_points({ { 0, 200 }, { 16, 4000 }, { 16, 300 } })   -- two points at a beat make a step
fade.enabled = false   fade:clear()   fade:remove()
fade:points()   fade:value_at(4)   bass:lanes()   bass:value_at("volume", 4)   synth:value_at("cutoff", 4)
```

- While the transport plays, an enabled lane sets its target at the start of each block, and offline renders do the same.
- A lane has priority over the fader and over `device:set`, which change the value of the track or the device, and `track.volume` and `device.params` read that value.
- When playback stops, the target keeps the last value of the lane, and it changes again when you set it or when playback starts.
- When you disable or remove a lane, the target gets its own value again.
- When you remove a device, paw removes its lanes, and when you move a device to another track, its lanes move with it.
- The project saves the lanes, undo applies to them, and they send `lane.added`, `lane.changed` and `lane.removed`.

### Lanes in the arrange view

`paw.lanes` shows lanes as rows of the arrange view.

| Function | Effect |
| --- | --- |
| `paw.lanes.open(track)`, `toggle`, `is_open` | show the lanes of a track |
| `paw.lanes.lines()` | each row: `{ track = id }` or `{ track = id, lane = id }` |
| `paw.lanes.name(lane)` | the name of a lane |
| `paw.lanes.format(lane, value)` | a value as text |
| `paw.lanes.value_at(lane, beat)` | the value at a beat |

`paw.groups.rows({ lanes = true })` gives the same rows as `lines()`, `paw.cursor.lane_id()` is the lane row under the cursor, and `paw.cursor.line()` is the place of the cursor among all the rows. Keys mapped with `view = "arrange.lane"` act on a lane row before the keys of the arrange view.
