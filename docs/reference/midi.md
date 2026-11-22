# MIDI

<!-- tags: midi midi-2 controller-moves event-list midi-output midi-files mpe -->

paw keeps MIDI at the resolution of MIDI 2.0. A MIDI clip holds notes and
controller moves. Tracks take MIDI from ports, and send MIDI to ports.
For why paw uses MIDI 2.0, see [About MIDI 2.0 in paw](../explanation/about-midi-2.md).
For MIDI controllers that move faders and parameters, see
[MIDI controllers](learn.md).

## Controller moves

A MIDI clip holds notes and controller moves: control changes, the pitch
wheel, pressure, registered and assignable controllers, and program
changes. The values are fractions, not seven-bit steps. A move with a
`key` belongs only to the note on that key: its own pitch bend, pressure
or controller, as in MIDI 2.0.

```lua
clip:set_controls({
  { start = 0, type = "cc", number = 64, value = 1 },         -- pedal down
  { start = 2, type = "bend", value = -0.5 },                 -- the wheel
  { start = 2, type = "bend", key = "E4", value = 1 / 48 },   -- one note, a semitone up
  { start = 4, type = "program", program = 12, bank = 258 },
})
track:midi({ type = "cc", number = 1, value = 0.3 })           -- now, to the track's devices
paw.on("midi.in", function(e) end)       -- everything that arrives at a port, for scripts; `e.port` names the port
paw.midi.ump({ type = "cc", number = 74, value = 1 })   -- as a MIDI 2.0 packet: two words
paw.midi.inject_ump({ 0x40903c00, 0xc0000000 })         -- and a packet, as if from a port
```

| Name | Effect |
| --- | --- |
| `clip:controls()` | The controller moves of the clip. |
| `clip:set_controls(list)` | Replace the controller moves. |
| `track:midi(event)` | Send an event to the devices of the track now. |
| `paw.midi.ump(event)` | The event as a MIDI 2.0 packet: two words. |
| `paw.midi.inject_ump(words)` | Inject a packet, as if from a port. |

The event `midi.in` comes for each message at a port. `e.port` names the
port.

A script can take controls of a controller for itself with the input
filter. A key or a controller in the filter does not sound and does not
record. Scripts still get its `midi.in` event, with `e.filtered = true`.

```lua
paw.api.engine_midi_filter("step", { { port = "nanoPAD", note = 36 }, { cc = 64 } })
paw.api.engine_midi_filter("step", nil)   -- removes the list of "step"
```

- Each rule has a `note` or a `cc` (0 to 127). `port` and `channel` (1 to
  16) are optional. Without them, the rule applies to all ports and
  channels.
- Each name keeps its own list. The filter is all the lists together, not
  more than 256 rules.
- The release of a key that a track holds always gets to the track. So no
  note continues to sound when the filter changes.

- paw records the controller moves with the notes.
- When playback starts in the middle of a clip, paw sends the last value
  of each controller before that point (chase).
- Cut, join, copy and undo keep the moves. The project file saves them
  exactly.

### Where controller moves go

| Device | What it gets |
| --- | --- |
| built-in `synth` | the wheel, the sustain pedal, and the bend of each note |
| CLAP plugin | the controllers of each note as note expressions. The other moves as MIDI 2.0 if the plugin takes it, else MIDI 1.0. |
| VST3 plugin | note expressions and poly pressure. Controllers through the parameters that the plugin assigns to them. |
| LV2 plugin, CLAP plugin with MIDI 1.0 only | MIDI 1.0. MIDI 1.0 has no bend for each note, so the controllers of a note do not reach these plugins. MPE for them is not available. |

### Note attributes

A note can have a MIDI 2.0 attribute, for example an articulation
(`note.attr`, see [The Lua interface](scripting.md)).

- paw records it from a MIDI 2.0 note-on.
- The `midi.in` event gives it as `e.attr`.
- paw sends it in the note-ons of MIDI 2.0 ports.
- It reaches CLAP plugins that prefer MIDI 2.0 notes, and Lua devices.
- For other devices, the `attr_map` of a track changes it into
  keyswitches and controllers.

## Edit controller moves

### Graphical window

The strip below the piano roll shows the velocities, or one controller
that you select in its dropdown.

| Gesture | Effect |
| --- | --- |
| Drag with the pointer | Draw the controller. |
| Drag with the right button | Draw a straight line: one move at each grid step (with Shift: each 32nd of a beat). |
| Click the head of a move | Select it. With Ctrl: add it to the selection or remove it. |
| Ctrl and a drag | Select the moves in a box. |
| Drag a selected head | Move the selected moves in time and value, on the grid. |
| `Delete`, `x` | Delete the selected moves. |
| Right click | A menu: select all, clear the selection, delete, clear the controller. |

### Terminal

`:controls.line cc 74 0 127` draws a line over the selection of the piano
roll, or over its full clip. Other forms: `:controls.line bend -8192 8191`,
`:controls.line pressure 0 127`.

## The event list

The event list shows each note and move of the clip in the piano roll, one
row each, in time order.

| Column | Value |
| --- | --- |
| time | bar.beat.hundredths |
| kind | `note`, `cc`, `bend`, `pressure`, `registered`, `assignable`, `program` |
| which | the pitch of a note, the number of a controller, the note that a move belongs to |
| value | a velocity, seven-bit steps with the fine part as decimals, the wheel from -8192 to 8191, the bend of a note in semitones |
| length | the length of a note |

`E` in the piano roll (`:notes.list`) shows the list over the terminal. In
the graphical window, List in the toolbar of the piano roll opens it in a
window of its own.

| Keys | Effect |
| --- | --- |
| `j` `k` | the next row, the previous row |
| `h` `l`, `<S-Tab>` `<Tab>` | the previous column, the next column |
| `<C-d>` `<C-u>` | ten rows down, ten rows up |
| `g` `G` | the first row, the last row |
| `<CR>`, `i`, `c`, double click | change the cell under the cursor |
| `x`, `d`, `<Del>` | delete the row |
| `a`, `o` | add a move at the time of the row |
| `u`, `<C-r>` | undo, redo |
| `q`, `<Esc>` | close |

Scripts use `paw.controls`: `rows`, `cells`, `edit`, `select_box`, `move`,
`line`.

## MIDI input

- paw reads MIDI from each ALSA sequencer port, which with PipeWire
  includes its MIDI devices, and from ports that appear later.
- A track names its port in `midi_input` by name. So paw finds the port
  again when you connect the keyboard later, or on a different computer.
- When a port goes away, paw releases the notes that were held on it. paw
  tells when the port goes away and when it returns, with the tracks that
  use it. The tracks use it again by its name.
- paw opens the ports only with a real audio device, or with
  `paw.api.engine_restart({ midi = true })` (see
  [Audio devices](audio-devices.md#test-backends)).

| Command, function | Effect |
| --- | --- |
| `:midi.inputs`, `paw.midi.inputs()` | List the input ports. |
| `:midi.select`, `paw.midi.select({ "Keystation" })` | Keep only some ports open, by id or a part of the name. `nil`: all ports. |
| `paw.midi.note_on("C4", 100)`, `paw.midi.note_off("C4")` | Play a note as if from a port (also on the null backend). |
| `paw.midi.inject({ type = "note_on", pitch = 60, velocity = 100, port = "Keys A" })` | Inject an event as if from a port. |
| `paw.midi.open_port("Guitar")` | Make a port of paw that other programs send to. PipeWire and the sequencer show it as `paw: Guitar`, and paw lists it with the inputs. A track takes it by that name. |
| `paw.midi.close_port("Guitar")` | Remove that port. |

Any program can send to a port of paw. The [vinput](../../extensions/vinput)
extension sends to such a port from a guitar.

### MIDI 2.0 at the ports

paw opens the sequencer as a MIDI 2.0 client and reads Universal MIDI
Packets. A MIDI 2.0 device arrives with all its data. A MIDI 1.0 device
arrives as the same events with less resolution. This needs a kernel built
with `CONFIG_SND_SEQ_UMP`. Without it, the ports are MIDI 1.0, and paw
widens what arrives by the rules of the specification, so both read the
same. paw does not support MIDI-CI (see [Limits](limits.md)).

## MIDI output

A track sends what it plays to a port. This is the notes and controllers
of its clips, and the MIDI input that passes through it, before its
devices.

| Way | Example |
| --- | --- |
| Lua | `track.midi_output = { port = "UM-ONE: UM-ONE MIDI 1", channel = 2 }` (`channel` nil keeps the channel of each message) |
| command | `:track.midi_out UM-ONE 2` (a part of the name is enough, `none` for no output) |
| lists | the MIDI out entries of the input list (`I`), and of the input menu on the track header in the graphical window |

`paw.midi.outputs()` lists the ports.

### Forms

paw sends MIDI 2.0 where the port takes it: when the sequencer has MIDI
2.0 (`CONFIG_SND_SEQ_UMP`) and the program of the port speaks it. Then the
notes, the bends and controllers of each note, and all values go as
Universal MIDI Packets with full resolution. Else paw sends MIDI 1.0, in
the form of the route. You set the form with `form` in
`track.midi_output`, with `:track.midi_out UM-ONE 2 mpe`, or with the MIDI
out form entries of the input list and the input menu.

| Form | Output |
| --- | --- |
| `auto` | Default. MIDI 2.0 where the port takes it, else `plain`. |
| `plain` | MIDI 1.0 as each message has it, in seven bits. paw does not send the bend and controllers of each note. The pressure of a note goes as poly pressure. |
| `mpe` | MIDI Polyphonic Expression (see below). |
| `cc14` | Control changes 0 to 31 as pairs of fourteen bits, with the fine part on 32 to 63. |

With `mpe`:

- Each note gets a channel of its own in the lower zone. Channel 1 is for
  the full instrument. The member channels start at 2. The zone has 15
  member channels unless you set `members`.
- The bend, pressure and brightness (controller 74) of a note are the
  pitch bend, pressure and controller 74 of its channel.
- paw first sends the zone (the MPE configuration message) with a bend
  range of 48 semitones, which is the bend range of a note in paw.
- A note takes the channel that was released first. Then a release that
  still sounds does not bend with the next note. If all channels are
  in use, the note shares the channel with the fewest notes.
- paw sends the moves that come for a note before its start on its
  channel, immediately before the note.

### Timing

- The audio thread puts a time stamp on each message. The stamp is when
  the message is heard, with the latency of the output and the delay of
  the plugins. It gives the
  message through a lock-free queue to a thread that schedules it on an
  ALSA sequencer queue in real time. So a synth on the port sounds with the
  tracks.
- A stop, a jump, and a turn of the loop end the notes that sound, with an
  All Notes Off on their channels. A removed port or a removed track does
  the same.
- Renders send nothing.
- paw opens the ports when it opens MIDI input (with an audio device, or
  `engine_restart({ midi = true })`).

### Ports of paw

`paw.midi.open_output("To Surge")` makes an output port of paw that other
programs read from (`paw out: To Surge`). A track that sends to `To Surge`
plays them. `paw.midi.close_output` removes the port.

Copies of a track send to the same port. Templates and project files keep
the port by its name.

On a kernel without `CONFIG_SND_SEQ_UMP`, only the MIDI 1.0 forms go
through a sequencer. The MIDI 2.0 output uses the same packets as the
plugins and the codec of the tests, but nobody tried it through a
sequencer.

## MIDI files

paw opens `.mid`, `.midi`, `.smf` and `.kar` files: format 0, 1 and 2, any
number of ticks for each beat, or SMPTE frames.

| Command | Effect |
| --- | --- |
| `:open song.mid`, `:e song.mid` | Open the file as a new project. |
| `:import song.mid` | Add the tracks of the file to the open project, below the track at the cursor, with the start of the file at the edit cursor, as one undo step. The tempo map of the project does not change. |
| `:import song.mid tempo=yes` | The same, and use the tempo map of the file from the cursor. |
| `:clip.import riff.mid` | Put all the notes of the file in one clip on the track at the cursor. |
| `:export song.mid` | Write the project as a format 1 file, with its tempo map, time signatures and markers. |
| `:export riff.mid clip` | Write the clip at the cursor. |
| `:export part.mid selection` | Write the selected tracks. |

A file that opens as a project gives:

- one track for each track of the file that has notes (paw splits a
  format 0 file by channel), with the name of the track, or "Channel N"
- one clip on each track, over the bars that it plays. Its controllers,
  pitch bend, pressure and program changes become controller moves of the
  clip (the curve editor shows them at `paw://clip/C/control/cc/N`).
- the tempo map, time signatures and markers of the file
- the lyrics, on the notes where they start (`note.meta.lyric`)
- the built-in drum kit on a track that plays only on channel 10. The
  other tracks have no instrument, as a new track has none.

The new project has no file: `:w` asks for a path, and never writes over
the `.mid` file. paw does not import what has no place in paw (sysex, key
signatures, text), and the message says how much it left out. In Lua, use
`paw.midifile` (see [The Lua interface](scripting.md)).
