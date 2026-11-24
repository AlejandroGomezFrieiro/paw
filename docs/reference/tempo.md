# Tempo and time signatures

<!-- tags: tempo time-signature timebase tempo-map -->

The tempo and the time signature can change along the song, and the module is
`paw.tempo`. For how the tempo map affects audio and MIDI, see
[About time and tempo](../explanation/about-time-and-tempo.md).

## Rules

- A tempo change holds until the next change, or ramps to it, and in a ramp
  the tempo changes linearly in time.
- A time signature change starts a new bar where it is, and if it is inside a
  bar, that bar is shorter.
- `paw.project.tempo` and the signature fields of the project are the
  values at the start. A project with one tempo and one signature saves as
  before.
- The engine follows the map sample by sample for the playhead, the loop,
  MIDI clips, automation, the metronome, recording and renders.
- The metronome accents the first beat of each bar and clicks on each
  beat of the signature, so a bar of 6/8 has six clicks.
- Plugins get the tempo, signature, bar and time for each block through the CLAP
  transport, the VST3 process context and the LV2 `time:Position`, and this works
  through the sandbox too.
- Each command below is one undo step.
- Inside a subproject, the commands change the tempo map of the song at
  the place of the block. A subproject with a tempo of its own
  (`:nest.time own`) has a map of its own, and `:tempo` there changes
  the subproject's tempo and leaves the song's map as it is. See
  [Subprojects](subprojects.md#its-own-tempo-and-meter).

## Commands

| Command | Effect |
| --- | --- |
| `:tempo` | Show the tempo at the start and at the cursor. |
| `:tempo 96` | Set the tempo at the start. |
| `:tempo 96 at 17` | Set the tempo from bar 17 (`17.3`: bar 17, beat 3). |
| `:tempo 96 here` | Set the tempo from the cursor. |
| `:tempo by=-1` | Change the tempo at the start by -1 BPM. |
| `:tempo.ramp` | Make the change at or before the cursor ramp to the next change. Again: hold. `:tempo.ramp off`: hold. |
| `:tempo.remove`, `:tempo.remove 17` | Remove the change at or before the cursor, or at bar 17. |
| `:tempo.list` | List the tempo and time signature changes. |
| `:tempo.tap`, `<Space>Tt` | Tap again and again, in time, to set the tempo at the cursor. |
| `:timesig 6/8` | Start 6/8 at the bar of the cursor. `:timesig 6/8 at 9`: at bar 9. |
| `:timesig` | Show the time signature at the cursor. |
| `:timesig.remove` | Remove the time signature change at the cursor, or at a bar. |

A tempo is from 1 to 999 BPM.

## Display

- The rulers number the bars and draw the bar and beat lines from the map.
- The arrange ruler of the terminal marks a tempo change `▾96` (`▾120>`
  for a ramp) and a signature change `‖6/8`. The mark is in the column of
  its beat. On a bar line, the bar's number follows the mark (`‖47 6/8`),
  and the value is cut when the next bar's number leaves no room for it.
  The graphical window marks them on its ruler.
- The status line and the transport of the graphical window show the
  tempo and signature at the playhead.

## Timebase of audio clips

An audio clip keeps its length in seconds, so a change of tempo does not
stretch or cut a recording, and the end beat of the clip comes from the
map. The `timebase` of the clip sets what it keeps of its start, as in the table below.

| `clip.timebase` | Effect |
| --- | --- |
| `"time"` | Default, as the audio items of REAPER. The start stays at the same second, so the clip moves in beats when the tempo before it changes. |
| `"beats"` | The start stays on its beat. |
| `"stretch"` | The start and the length stay on their beats. paw stretches the sound to fit (see [Stretched and repeating clips](stretch.md#follow-the-tempo)). |

MIDI clips and automation stay on their beats.

## Lua

```lua
paw.tempo.set(17, 96)                    -- 96 BPM from beat 17 on
paw.tempo.set(32, 120, { ramp = true })  -- ramp from 120 at beat 32 to the next change
paw.tempo.set_signature(9, 6, 8)         -- 6/8 from bar 9
paw.tempo.at(40)  paw.tempo.signature_at(40)  paw.tempo.points()  paw.tempo.remove(17)
paw.tempo.beats_to_seconds(16)  paw.tempo.seconds_to_beats(8)  paw.tempo.bar_of(33)
paw.time.format(33.5)                    -- "9.4.00": bar 9, fourth eighth
```

| Function | Result |
| --- | --- |
| `paw.tempo.set(beat, bpm, opts)` | Set a tempo change. `{ ramp = true }`: ramp to the next change. |
| `paw.tempo.remove(beat)` | Remove a tempo change. |
| `paw.tempo.at(beat)` | The tempo at a beat. |
| `paw.tempo.points()` | The tempo changes. |
| `paw.tempo.set_signature(bar, num, den)` | Set a time signature from a bar. |
| `paw.tempo.remove_signature(bar)` | Remove a time signature change. |
| `paw.tempo.signature_at(beat)` | The time signature at a beat. |
| `paw.tempo.signatures()` | The time signature changes. |
| `paw.tempo.set_points(tempos, signatures)` | Replace the map. |
| `paw.tempo.beats_to_seconds(beat)`, `paw.tempo.seconds_to_beats(s)` | Convert a position. |
| `paw.tempo.seconds_between(from, to)` | The seconds between two beats. |
| `paw.tempo.bar_of(beat)`, `paw.tempo.bar_start(n)` | The bar of a beat, the first beat of bar n. |
| `paw.time.format(beat)` | A position as bar.beat.hundredths. |
