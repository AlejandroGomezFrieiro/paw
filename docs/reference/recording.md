# Recording

<!-- tags: recording input-and-recording inputs monitoring -->

A track records audio from the input device, or MIDI from the MIDI ports.
For the devices, see [Audio devices](audio-devices.md), for MIDI ports and
MIDI files, see [MIDI](midi.md), and for the takes that recording makes, see
[Takes](takes.md).

## The input of a track

A track takes audio from one channel, or from a pair of adjacent channels,
of the input device. The input goes into the track before its devices, so a
guitar goes through the amp simulator on its track.

```lua
local gtr = paw.add_track({ name = "Guitar" })
gtr.input = "1/2"            -- or "1", "3", nil for none
gtr.monitor = true           -- hear it without arming
gtr.armed = true             -- record it
paw.transport.record()       -- recording on, and play
paw.transport.stop()         -- the take becomes a clip at the position recording began
paw.transport.recording = false

local keys = paw.add_track({ name = "Keys" })
keys.midi_input = { port = "Keystation 49", channel = 1 }   -- MIDI from one port (and channel); nil for all
```

| Field of a track | Value |
| --- | --- |
| `input` | `"1"`, `"1/2"`, `"3"`, or nil for no audio input. A pair is two adjacent channels, so `"1/3"` is an error. A project file with a bad input does not load. |
| `monitor` | True: you hear the input, also when the track is not armed. |
| `armed` | True: the track records. |
| `midi_input` | `{ port, channel }`: MIDI from one port, and optionally one channel. Nil: all ports. |

### The input list

`I` in the arrange view (or the input button on the track header in the
graphical window) lists all the inputs of a track:

| Heading | Entries |
| --- | --- |
| audio | no audio input, each channel, each adjacent pair, named with the device: `UR22mkII · 1`, `UR22mkII · 1/2` |
| MIDI | all ports, or one port |
| MIDI channel | all channels, or one channel |
| MIDI out | the port and channel where the track sends MIDI (see [MIDI](midi.md#midi-output)) |

- A choice that is saved but not available now (a pair that the device
  does not have, a port that is disconnected) shows as selected, with the
  mark `missing`.
- `paw.audio.choices(track)` gives the list, and
  `paw.audio.choose(track, choice)` selects an entry.

| Command | Effect |
| --- | --- |
| `:track.input 1/2` | Set the audio input of the track. |
| `:track.midi Keystation ch=1` | Set the MIDI input of the track: a port by a part of its name, and a channel. |

`Tab` completes the port and the channel.

### The header

- The track header shows the input (`UR22mkII · 1/2`) and the level at the
  input, and the level shows even when the track is not armed or monitored.
- While a track is armed or monitored, its meters, the master's meters
  and a tuner on it move with the input, even when the song is stopped.
- In the terminal, `I` next to `M S R` on the header switches the monitor
  on or off. In the graphical window, the loudspeaker next to the input
  button does the same. `<A-i>` also switches the monitor.

## Rules

- **Monitor.** You hear the input of a track when the track is armed, or
  when its monitor is on. An armed track always monitors, so what you hear
  is what paw records. A track with no input ignores both. A track without
  an audio input that is monitored plays MIDI input, and records nothing.
- **The selected track plays the keyboard.** While no track is armed, the
  track of the cursor plays MIDI input as if its monitor is on, and it
  records nothing. `paw.opt.midi_follows_selection = false` turns the
  behavior off, and the project does not change.
- **What records.** While `paw.transport.recording` is on and the
  transport plays:
  - each armed track with an audio input records its dry input (before
    its devices) to a WAV file.
  - each armed track without an audio input plays and records MIDI input:
    from all ports, or from the port (and channel) of its `midi_input`.
- **Where a take starts.** `R` (`:transport.record`) with the song
  stopped moves the playhead to the cursor and records from there, as
  `<Space><Space>` plays from the cursor. If you put the playhead on
  purpose (`gs`, `gp`, a click on the ruler) and did not move the cursor
  after that, `R` records from the playhead, and it also does so while the
  song plays. `paw.transport.record()` always records from the playhead. With `paw.opt.play_from = "playhead"`, `R` still records from
  the cursor, and `<Space><Space>` plays from the playhead.
- **What you hear while you record.** An armed track with an audio input
  plays only its input while the take records, so its clips under the take
  are silent. With a punch, its clips play before
  the punch in and after the punch out. Other tracks play as usual.
- **The end of a take.** A stop, or recording off, ends the take, and a seek
  starts a new take. paw adds the clips of a take, audio and MIDI, as one
  undo step, and it cuts notes that are held at the end.
- **A recording round the loop.** With the loop on, recording continues
  round the loop, and each time round becomes a take of one clip over the
  loop (see [Takes](takes.md)). The last take plays, and the name of the
  clip shows which take it is (`take 3 ‹3/3›`).
  - What you played before the loop start becomes a separate clip before
    it.
  - The first time round counts if it started at the loop start or
    before. The last time round counts if it reached at least half of the
    loop.
  - With the loop off, a take is one clip.

## Count-in

`paw.opt.count_in` is the number of bars that the metronome counts before
a take that starts with the song stopped. 0 (the default) gives no
count-in.

| Keys, command | Effect |
| --- | --- |
| `:countin 1` | Count one bar. |
| `:countin off` | No count-in. |
| `:countin`, `gM` | Count-in on or off. |

- The record button, `R` and `paw.transport.record()` count in. Play with
  record mode on also counts in. A punch in by hand while the song plays
  does not.
- The clicks use the tempo and time signature at the playhead. paw plays
  one click on each beat, and a higher click on the first beat of each bar. They
  sound when the metronome is off too, with the same latency as the song.
- The playhead does not move during the count, and the song and the take
  start on the frame after the count, so the recording lines up as it does
  without a count-in.
- `paw.transport.counting` is the number of beats that remain (0 when no
  count runs). The status line and the clock of the graphical window show
  `count 3`, and the record button blinks on the beats.
- A stop, or `Esc`, during the count cancels it, which leaves no take,
  nothing recorded, and record mode off.

## The click

The metronome and the count-in play the same click, and the commands below set it.

| Command | Effect |
| --- | --- |
| `:click` | Shows the level, the accent and the output of the click. |
| `:click level=-6` | The level of the click in dB, -60 to +12 (`paw.opt.click_level`). |
| `:click accent=off` | The same click on each beat. `accent=on`: a higher click on the first beat of a bar (`paw.opt.click_accent`). |
| `:click output=3` | The click plays on outputs 3 and 4 of the audio device, and not in the main output (`paw.opt.click_output`). `output=song`: with the song. |

- An output that the device does not have plays no click.
- A render never has the click.

## MIDI overdub

`paw.opt.midi_record` tells what a MIDI take over a clip becomes.

- `"new"` (the default): the take is a clip of its own, on top of the
  clip. `J` or `:j` merges them later.
- `"merge"`: when the take ends, paw joins its notes into the MIDI clips
  that it is over, in the same undo step as the take. A take round a loop
  stays a clip of takes.

## Punch in and out

With `paw.transport.punch_enabled` on, a take records only from
`punch_start` to `punch_end` (in beats). The song plays before and after.

- Recording starts and stops on the frames at those points, so the clip
  covers the range exactly, and a note held across the punch out is cut there.
- If recording starts inside the range, it records from the playhead to
  the punch out. If it starts after the range, it records nothing and
  says so.
- With the loop on too, each time through the range is a take of one clip
  over it. The first time counts if it started at the punch in or before.
  The last time counts if it reached at least half of the range. A range
  that goes past the loop end is cut there.
- The range is saved with the project, as the loop is, and undo does not
  change it.
- The range is red on the ruler of both frontends. In the graphical
  window, it is below the loop, you drag its ends as you drag the ends of the
  loop, and the timeline menu has the entries.

| Keys, command | Effect |
| --- | --- |
| `:punch` | Punch on or off. The first `:punch` with no range set uses the visual selection, or the loop. |
| `:punch 5 8` | Punch over bars 5 to 8 (as `:transport.loop` counts them). |
| `:punch selection` | Punch over the visual selection, or the loop if there is no selection. |
| `gI` | Punch on or off. On a selection: punch over it. |

## Pre-roll

The pre-roll is how long the song plays before the punch in, for a take
that starts from a stop.

| Option | Range | Effect |
| --- | --- | --- |
| `paw.opt.pre_roll` | 0 to 16 bars | Whole bars before the punch in. |
| `paw.opt.pre_roll_seconds` | 0 to 30 s | Seconds before that. |

| Command | Effect |
| --- | --- |
| `:preroll 2` | Two bars. |
| `:preroll 3s` | Three seconds. |
| `:preroll off` | No pre-roll. |
| `:preroll` | Pre-roll on or off. |

The timeline menu of the graphical window has the same entries.

- Pre-roll applies when punch is on, the transport is stopped, and recording
  starts. The playhead moves back by the bars, from the bar line at or
  before the punch in, and then by the seconds, and the song plays from there.
- paw records nothing until the punch in, so the take starts on the frame of
  the punch in and the clip starts exactly there.
- A playhead that is already further back does not move.
- A playhead inside or after the range gets no pre-roll. A take that
  starts while the song plays, or a take without punch, also gets no
  pre-roll.
- A count-in comes before the pre-roll. It counts at the start of the
  pre-roll, and then the song plays from there.
- The pre-roll belongs to you, as the count-in does, and it is not saved with
  a project.

## Recording offset

Sound that you play with the song is heard late and arrives late, so paw
moves each take earlier by the latency that the audio system reports, plus
`paw.transport.record_offset` milliseconds for the latency that it does not
report. See
[How to set the recording offset](../how-to/set-the-recording-offset.md).

## Files

- Recordings go into the `media` directory next to the project file.
- A project that is not saved records into
  `~/.local/share/paw/recordings`. When you save it, paw links or copies
  these files into `media` next to it, and points the clips there. The
  original files stay for the earlier undo steps.
- Every two seconds, paw updates the WAV header of a take and writes the
  file to the disk, so a file that a crash or a power loss leaves is a
  valid WAV with all but its last seconds.
- The safety copy contains the take from its start. After a crash,
  `:recover` puts the take back as a clip where it started, on its track.
- If the `media` directory holds takes that no clip uses and that paw
  wrote after the last save, paw says so when the project opens.
  `:recover` lists them so that you can add them on the track that recorded
  them, and it works even after you move the project folder.
- If paw cannot write a file (the disk is full), recording stops. paw
  keeps what it wrote as a clip, and a message gives the reason.
- If the disk has room for less than `paw.opt.record_warn_minutes` (30)
  minutes when recording starts, paw says how many minutes remain.

## Import sound files

| Way | Effect |
| --- | --- |
| `:import take.mp3` | Import a sound file. With no name, it shows a list of files. |
| `:clip.import` | Put a file on the track at the cursor. |
| `paw.import_audio(path, { track = ..., start = ... })` | Import in Lua. |
| a file name on the command line | Open the file where a project would open. |

`paw.pick.file` is the list of files that extensions use.
