# vinput

This extension adds virtual inputs. A virtual input is a chain that changes another kind of signal into an input that
a track can take, and the only kind now changes a guitar into MIDI. You play
chords or single notes into the audio interface, and a track gets them as
notes, either to play an instrument or to record.

```
 source            level        gdi2m            notes           MIDI port
 UR22mkII Input 2 ─▶ × 1.20 ─▶ hears the notes ─▶ channel 1 ─▶ “Guitar” ─▶ any track
```

[gdi2m](https://github.com/maximmashkov1/gdi2m), a small neural network,
hears the notes. It is a separate program that runs beside paw, it takes the audio
from the port itself, and it sends its notes to a MIDI port that paw makes
for it, so no part of it runs on the audio thread of paw.

```lua
paw.ext.load("/path/to/paw/extensions/vinput")   -- or link it into ~/.config/paw/extensions
```

## Try it

1. Connect the guitar to input 2 of the audio interface. Start paw with
   the real audio device.
2. Type `:ext.load vinput`, then `:vinput.add Guitar`, and the panel of
   inputs opens.
3. Press `s` and choose the port of input 2, and after a moment the state of
   the input is `running`.
4. Press `t`, and a new track takes the input, with an instrument, and is
   armed.
5. Play a chord on the guitar, and you hear the chord on the instrument. The
   panel shows the level that the tracker hears and the notes that it
   sent.

## How to

### How to play an instrument from the guitar

1. Make an input with `:vinput.add Guitar`, and choose its source with
   `s`.
2. Put the cursor on the track of the instrument. Press `I` and choose
   `Guitar`, or type `:track.midi Guitar`.
3. Arm the track.

From Lua:

```lua
local vinput = require("vinput")
vinput.add({ name = "Guitar", source = "Input 2", gain = 1.2 })
local track = paw.add_track({ name = "Pad" })
track:add_device("synth")
track.midi_input = { port = "Guitar" }            -- as for any MIDI port
track.armed = true                                -- hear it, record it
```

### How to correct the level

1. Play for some time while the input runs.
2. Press `ga` in the panel, or type `:vinput.gain`, and the gain becomes the
   value that the tracker asked for.

The tracker wants a level of about -18 dBFS while you play.

### How to get fewer wrong notes

- Lower the gain until the level is near −18 dBFS.
- Raise the threshold with `:vinput.set threshold 0.9`.
- Tune the guitar to A440.

### How to send high notes on another channel

Type `:vinput.set split E3:2`, and notes from E3 up go on channel 2.

### In the graphical window

- Choose "Virtual inputs…" in the `Track` button or in the menu of the
  timeline.
- Choose "New track from a virtual input". paw makes the first input if
  there is none, makes a track that takes it, and then shows the inputs so that you can
  choose the source.

## Reference

### What it needs

- **gdi2m** with its model. paw looks for it in `paw.opt.vinput_gdi2m`,
  `$GDI2M`, on the `PATH`, and in `~/guitar_tracker/result/bin`.
- **PipeWire**. gdi2m finds the audio port and the MIDI port of paw
  through it.
- **A real audio device** in paw. On the null backend, the MIDI ports are
  not open and no tracker starts, but `paw.opt.vinput_run = true` starts the trackers
  anyway.
- **A guitar tuned to A440**, dry, directly into the interface. A quarter
  tone out of tune breaks chords, and no
  setting changes that, because it comes from how the tracker works.

### The panel

`<localleader>i` (`:vinput`) shows the inputs. Each input shows its chain and
its state, with its settings under them.

| Setting | Effect |
| --- | --- |
| Name | the MIDI port that tracks take, and the tracks follow when you rename it |
| Source | the audio port of the guitar, from the ports that gdi2m lists |
| Gain | the level before the tracker, which was trained at one level (0.1 to 8). After a run with sound, the tracker reports the gain that it prefers, and `ga` or the button beside the slider takes it |
| Threshold | how sure the tracker must be to start a note (0.85). A lower value finds more notes, and more wrong notes |
| Damping | how far the level must fall, in dB, for damped strings to end every note (20). 0 leaves it to the tracker |
| Ringing | how sure the tracker must stay that a note still rings (0.35). A lower value holds notes longer |
| Velocity | always 100, or as hard as you picked the string |
| Channel | the MIDI channel of the notes |
| Split | notes from a pitch up on another channel: `E3:2`, or up to three, `E3:2, E4:3` |

| Keys in the panel | Effect |
| --- | --- |
| `j` `k`, `gg` `G` | move along the rows |
| `+` `-`, `Ctrl-a` `Ctrl-x` | less and more of a setting, by one step (a count multiplies, as in `10+`). On a heading, off and on |
| `Enter` | on a heading, turns the input on or off. On a setting, flips it, chooses it from a list, or lets you type it |
| `x` | the usual value of the setting |
| `o` | the input on or off |
| `s` | chooses the source |
| `ga` | takes the gain that the tracker asked for |
| `a`, `D` | adds an input, or removes this input |
| `t` | makes a track that takes the input, with an instrument, armed |
| `r`, `gR` | starts the tracker again, or finds the audio ports again |
| `Esc` | cancels, and the panel stays |
| `Ctrl-w p` | returns to the window before |

In the graphical window:

- Each input has a tab, and `+ Add` adds one.
- The chain shows as boxes. A click on the source opens the ports, a click
  on the port opens its name, and a click on gdi2m starts it again.
- You drag sliders, move them with the wheel, and reset them with a double
  click.
- The bottom line tells what the tracker does.
- Every key of the panel works there too.

### Commands

| Command | Effect |
| --- | --- |
| `vinput [name]` | shows the inputs |
| `vinput.add [name] [source=… gain=…]` | adds a guitar-to-MIDI input |
| `vinput.source [part of a port's name]` | chooses the source from a list, or sets it |
| `vinput.set <setting> <value> [input=name]` | changes a setting, as in `vinput.set threshold 0.8` |
| `vinput.on`, `vinput.off`, `vinput.restart`, `vinput.remove` `[name]` | turns the input on or off, starts it again, or removes it |
| `vinput.gain [name]` | takes the gain that the tracker asked for after its last run |
| `vinput.track [name] [instrument]` | makes a track that takes the input |
| `vinput.status` | shows the state of every input |

A track takes an input where it takes any MIDI port: `in` on its header in
the graphical window, `I` in the terminal, `:track.midi Guitar`.

### States of an input

| State | Meaning |
| --- | --- |
| off | it is off, or paw has no real audio device |
| not ready | no source is chosen, or paw did not find gdi2m |
| starting | the tracker starts, and it starts again after each change to a setting |
| running | shows the level that the tracker hears (it wants about -18 dBFS while you play), the notes that it sent, and the milliseconds that it takes for each 5.3 ms of sound |
| stopped | the tracker stopped four times in a row, and the panel shows its last output. A change to a setting, or `r`, tries again |

While an input is on, its tracker uses about half of one processor core,
even when you do not play, so turn the input off when you do not need it.

### Files

- The inputs belong to the machine and not to a project, because they name
  audio ports of this computer.
- paw keeps them in `~/.local/state/paw/vinput.json`
  (`paw.opt.vinput_file` names another file), and they are there at the next
  start.
- A project keeps only the name of the port that its tracks take.
- The output of each tracker goes to `vinput/<name>.log` beside that file.

### How it works

- `paw.midi.open_port(name)` makes a MIDI port of paw. PipeWire shows it to
  other programs as `paw:<name>`, and whatever arrives there goes to the tracks
  that chose `name`.
- The extension runs `gdi2m live --device <source> --port "paw:<name>
  (playback)"` with the settings of the input, through
  `paw.api.proc_spawn`. A change to a setting stops that program and
  starts it with the new values, which takes about a second.
- paw asks the program to stop (`paw.api.proc_stop`), so that it sends its
  note-offs. If paw must kill the program, paw makes the port again, which releases
  the held notes. In all cases the program also stops when paw stops.
- A kind of input is a table in `require("vinput").kinds`. The table has
  the stages and their settings, the command to run, and how to read the
  output of the program, so to add a kind you add a table.

### Events

| Event | Payload | When |
| --- | --- | --- |
| `vinput.changed` | `{}` | a virtual input changed, by being added, removed or set |

### Limits

- The extension has no pitch bends and no vibrato, because every note is a whole semitone, and two
  strings that play the same pitch make one note.
- A change of a setting makes a gap, because the tracker starts again.
- The chain has no audio effects before the tracker and no MIDI effects after it, because the
  stages of the chain are the stages of gdi2m.
- Two DAWs at the same time with an input of the same name do not work, because the
  tracker cannot tell their ports apart, and it tells you.
- The extension does not run without PipeWire.
