# Stretched and repeating clips

<!-- tags: stretching-and-looping-clips stretch warp loop pitch formants -->

An audio clip can play its file longer or shorter at the same pitch, play it
higher or lower at the same length, and play it in time with any tempo, and any clip
can loop. Each of these is a field of the clip, which the project saves and
which copy, paste, cut and undo keep. The module is `paw.stretch`. For the
stretch methods, see [About time stretch](../explanation/about-stretching.md).

## Commands

| Keys, command | Effect |
| --- | --- |
| `:clip.stretch 1.5` | Play the file 1.5 times as long (2 is half speed). The clip becomes longer with it. |
| `:clip.stretch to=8` | Stretch what the clip plays to 8 beats. |
| `:clip.stretch selection`, `:clip.stretch loop` | Stretch it over the time selection, or over the loop. |
| `:clip.stretch reset` | Play the file at its own speed again. |
| `:clip.pitch 3`, `:clip.pitch -0.5` | Play it 3 semitones higher, or a quarter tone lower, at the same length. |
| `:clip.tempo` | Follow the tempo, from the tempo at which the clip plays now. |
| `:clip.tempo 100` | Follow the tempo: the sound of the clip is at 100 BPM. |
| `:clip.tempo off` | Keep its seconds again. |
| `:clip.stretch_mode tonal` | The method: `tonal`, `percussive` or `auto`. |
| `:clip.formants`, `:clip.formants on`, `:clip.formants off` | Keep the formants when the pitch changes: switch, on, off. |
| `:clip.warp`, `gw` | Put a warp marker at the cursor. |
| `:clip.warp move` | Move the warp marker nearest the cursor to the cursor. `:clip.warp move 2`: marker 2. `:clip.warp move 2 8.5`: marker 2 to beat 8.5. |
| `:clip.warp remove`, `gW` | Remove the warp marker nearest the cursor. |
| `:clip.warp snap` | Move each warp marker to the grid. |
| `:clip.warp clear` | Remove all the warp markers. |
| `:clip.repeat` | Make the clip repeat its content when you make it longer, or stop the repeat. It is not the playback loop. |
| `:clip.repeat 4` | Repeat 4 beats. |
| `:clip.repeat off` | Stop the repeat. |

## Graphical window

| Gesture | Effect |
| --- | --- |
| Alt, Shift and a drag of the right edge of an audio clip | Stretch the clip to that point, on the grid. |
| Double click on the top band of a clip | Put a warp marker there. |
| Drag the handle of a warp marker | Move the marker. |
| The menu of a clip, "Stretch and loop" | The other actions. |

## Labels

A stretched clip has a label before its name, in both frontends:

| Label | Meaning |
| --- | --- |
| `×1.5` | stretched |
| `+3st` | pitch shifted |
| `♩` | follows the tempo |
| `↻` | repeats |
| `stretching…` | paw makes its sound now |

## Stretch

| Field | Value |
| --- | --- |
| `clip.stretch` | The ratio, from 0.25 to 4. A change of this field does not change the length of the clip. |
| `clip.pitch` | Semitones, fractions allowed, up to 24 in each direction. |
| `clip.stretch_mode` | `"tonal"`, `"percussive"` or `"auto"` (default). |
| `clip.formants` | True: keep the formants when the pitch changes. Then the clip uses the `tonal` method in all modes. |
| `clip.made` | How much of the stretched sound is ready, from 0 to 1. |
| `clip.preview` | True while the clip plays a rough preview, before paw starts its stretched sound. |
| `clip.offset` | In seconds of the file. One second of a clip stretched by 2 is half a second of its file. |

- A stretched or shifted clip does not stretch while it plays. paw
  stretches its file once, on a thread of its own, and the engine
  plays the result as it plays any file.
- paw starts the stretch a moment after the last change, and a drag starts it
  once, when you release the edge.
- Until paw starts, the clip plays a rough preview, which is short pieces of its
  file at the pitch of the file, each where the stretch puts it, so you hear
  the rhythm and not silence. A render never uses the preview.
- paw makes the clips that the playhead plays in the next 10
  seconds first, or, when the song is stopped, the clips after the cursor.
  Then it makes the clips that you see in a window of the arrange view,
  then the clips that a render waits for, and then the rest.
- When paw is busy with other clips, a clip that plays soon or that you
  see takes the place of one of the rest, which starts again later.
- paw makes the sound from its start, into space for all of it, and the
  clip plays it as far as it is ready. paw makes it many times faster than
  it plays, so a long file plays immediately.
- The playhead can be past the ready part, for example far into a long
  clip that changed a short time before. In that case the clip fades out
  just before that point, is silent, and fades in where the ready part reaches.
- A render waits until all of the sound is ready, so a render gives the same
  file at any time.
- paw keeps each stretched version by the bytes of its file, warp
  markers, shift, method, formants and sample rate. A large version goes
  in the bake cache, and paw finds it there in later runs and for other
  projects, even after you move the file.

## Warp markers

A warp marker pins a moment of the file to a place in the clip. Each part
of the sound between two markers stretches by its own amount. For example,
you can put a marker on each beat of a part that is not in time, and then move each
marker to its beat, or move all of them with `:clip.warp snap`.

- A new marker changes nothing.
- A move of a marker stretches the sound between it and its two neighbors,
  and nowhere else. If no marker is between it and the start or end of the
  clip, paw first pins that edge with a marker.
- A marker cannot move further than a stretch of 0.25 to 4 on each side
  allows.
- In the terminal, a marker is a yellow line on the name row of the clip,
  on the left edge of the cell, so the cells under it still show the sound.
  In the graphical window, it is a yellow line with a handle on the top band
  of the clip.
- The project saves the markers, copy and cut keep them, and undo changes
  them like any edit. They stay pinned to the file when you trim or slip the
  clip.

`clip.warp` is a list of `{ source, target, beat }`:

| Field | Value |
| --- | --- |
| `source` | The moment of the file, in seconds. |
| `beat` | Where the moment plays now. |
| `target` | Where the moment plays with no markers, in seconds of the file before the stretch of the clip. The project saves this field. The stretch of the clip still applies to the whole. |

## Follow the tempo

A clip in the `stretch` timebase (`:clip.tempo`, or
`clip.timebase = "stretch"`) keeps its start and its length on their beats
when the tempo changes. Its stretch changes to fit, and its pitch stays.

- `clip.source_tempo` is the tempo of the sound of the clip. paw sets it
  when the timebase changes to `stretch` (the tempo at the start of the
  clip, times its stretch). You can also set it, so `:clip.tempo 100` makes a loop
  recorded at 100 BPM play at the tempo of the song. Recording sets it on
  each clip of a take, to the tempo of the recording.
- Where the tempo changes inside such a clip (a ramp, or a change in the
  middle), paw does not stretch it evenly and instead bends it along the tempo
  map, so that each beat of its sound, at `clip.source_tempo`, plays on a beat of
  the song, and `clip.bent` is then true.
- paw stretches a repeating clip evenly in all cases.

## Repeat

A repeating clip (`:clip.repeat`, field `clip.loop`) repeats `clip.loop_length` beats of what it
plays over its full length. When you drag its end out, the content repeats,
and a notch marks each repeat in both frontends. In the terminal the notch is on the name row of the clip, after its name, so the cells under it still show the notes or the sound.

| Field | Value |
| --- | --- |
| `clip.loop` | True: the clip repeats its content. The name stays `loop` because `repeat` is a Lua keyword. |
| `clip.loop_length` | The repeat, in beats. Default when the loop starts: the length of the clip for MIDI, the rest of the file from the start of the clip for audio. An audio clip measures its repeat in seconds at its start, as its sound. |
| `clip.loop_start` | Where the repeated part starts, from the start of the clip (0 or less). |

- The repeats are the same, sample for sample, because audio plays again from the
  same file. paw puts a fade of some milliseconds at the joins only where
  the sound does not continue into its own start, and MIDI notes play again,
  each cut at the end of its repeat.
- A trim of the start turns the loop instead of using more of the file, and
  the rest plays where it played. A drag of the start out again brings
  back earlier repeats, and Alt and an edge slips the pattern inside the clip.
- A cut gives the full loop to both pieces, each from where it starts, so
  the pieces sound as the clip did. A cut through sound fades out and in
  over 3 ms, as any cut does.
- A fade-in belongs to the first repeat and a fade-out to the last, and each
  is no longer than its repeat.
- For takes in stretched and repeating clips, see
  [Takes](takes.md#stretch-and-loop).

## Lua

| Function | Effect |
| --- | --- |
| `paw.stretch.set(clip, 1.5)` | Stretch by a ratio. |
| `paw.stretch.to(clip, 8)` | Stretch to 8 beats. |
| `paw.stretch.fit(clip, from, to)` | Stretch over a range. |
| `paw.stretch.reset(clip)` | No stretch. |
| `paw.stretch.pitch(clip, 3)` | Shift the pitch. |
| `paw.stretch.follow(clip, bpm)` | Follow the tempo. |
| `paw.stretch.loop(clip, true, 4)` | Repeat 4 beats. |
| `paw.stretch.warp_add(clip, beat)` | Add a warp marker. |
| `paw.stretch.warp_move(clip, i, beat)` | Move marker i. |
| `paw.stretch.warp_remove(clip, i)` | Remove marker i. |
| `paw.stretch.warp_snap(clip)` | Move the markers to the grid. |
| `clip.warp = {}` | Remove all the markers. |
