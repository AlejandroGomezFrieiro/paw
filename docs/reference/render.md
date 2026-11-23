# Render

<!-- tags: render rendering export stems bounce render-tags -->

A render writes the song, a part of it, or its tracks to sound files. For
the steps, see [How to export a song as WAV, FLAC or MP3](../how-to/export-a-song.md) and
[How to render stems](../how-to/render-stems.md).

## Commands

| Command | Effect |
| --- | --- |
| `:export` | Export the song, a part of it, or its tracks to sound files (see `:export`). |
| `:export!` | The same, with no plan first, and it replaces files. |
| `:export.cancel` | Stop the export and the files that wait after it. |
| `:render mix.flac` | Render the song to a file (see below). |
| `:render.cancel` | Stop the render. |
| `:render.tags` | Show or set the tags of the project (see Tags). |
| `:render stems` | Render one file for each group (see Stems). |
| `:render.regions out` | Render each region to a file of its own (see Regions). |
| `:stems out` | Render one file for each track into `out` (default: `renders/stems`), as `:export out/ each=track` does. |
| `:bounce` | Render tracks to a new audio track (see Bounce). |

## `:export`

`:export` writes the mix of the song to `renders/<project>.wav` in the
folder of the project. A range before the command chooses the tracks and
the time, as it does for each command that takes a range (see
[Ex commands](ex.md#ranges-of-time)), and the words after it choose the files:

```
:[tracks] [time] export[!] [preset] [target] [word=value ...]
```

| Line | What paw writes |
| --- | --- |
| `:export` | the song, through the master, to `renders/song.wav` |
| `:export song.flac` | the song as a FLAC file |
| `:17,32export bridge.wav` | bars 17 to 32 |
| `:export in=loop loop.wav` | the loop |
| `:export in=Chorus` | the region Chorus |
| `:t/Drums/export drums.wav` | the group Drums alone, through the master |
| `:t2,t4export` | tracks 2 to 4 as one file, `renders/<names>.wav` |
| `:'<,'>export` | the tracks and the time of the selection |
| `:export stems` | one file for each group (a preset, see below) |
| `:export tracks` | one file for each track |
| `:export regions` | one file for each region |
| `:export each=region,group` | one file for each group in each region |

An ending of another program's file, such as `.mid` or `.rpp`, writes that
format instead (see [MIDI](midi.md), and `:help formats` for the list).

### The words

| Word | Values | Default |
| --- | --- | --- |
| `each=` | `group`, `track`, `region`, `clip`, or two joined: `region,group` | one file |
| `tap=` | `pre`, `post`, `groups`, `master` (see the table of `tap` under Lua) | `master` |
| `channels=` | `stereo`, `mono`, or `auto` (one channel when both sides are equal) | `stereo` |
| `in=` | `loop`, or the name of a region | the song |
| `format=` | `wav`, `flac`, `mp3`, `ogg`, `opus`, when the target has no ending | `wav` |
| `level=` | with `each=region`: a level from 1, or `leaves` | every region |
| `wait=true` | export in the foreground | |
| `tail=`, `rate=`, `bits=`, `dither=`, `quality=`, `bitrate=`, `normalize=`, `loudness=`, and the tags | as for `:render` below | `tail=2` |

- `each=group` makes one file for each group at the top level, and one for
  each track outside a group. In a window narrowed to a group, the top
  level is the inside of the group.
- `each=track` makes one file for each track that has clips. With a range,
  a group of the range gives the tracks inside it.
- `tap=pre` and `tap=post` need tracks: a range of tracks, or
  `each=group`, `each=track` or `each=clip`.
- A word typed after a preset changes the word of the preset:
  `:export stems format=flac`.

### Presets

| Preset | Words | Files |
| --- | --- | --- |
| `mix` | none | `{project}.wav` |
| `review` | `quality=high loudness=-14` | `{project}.mp3` |
| `stems` | `each=group tap=master channels=auto` | `stems/{group}.wav` |
| `tracks` | `each=track tap=post channels=auto` | `tracks/{track}.wav` |
| `regions` | `each=region` | `regions/{n} {region}.wav` |

`paw.export.presets.<name> = { target = "...", words = { ... } }` in
`init.lua` adds a preset.

### Names and folders

The target is a file, a folder that ends in `/`, or a name with fields:

| Field | What it holds |
| --- | --- |
| `{project}` | the name of the project |
| `{track}`, `{group}` | the name of the track or group of the file |
| `{tracks}` | the names of the range, joined with `+` |
| `{region}` | the name of the region, with the regions around it: `Chorus 2 - Verse A` |
| `{n}` | the number of the file in the set, with two digits |
| `{date}` | the date, as `2026-11-23` |

- A name with no folder goes into `renders/` of the project. A path with a
  folder goes there, and `~/` is the home folder.
- With `each=` and a target without its field, paw adds the field:
  `:export stems out/` writes `out/Drums.wav`.
- When two files get the same name, the second one gets a number:
  `Bass 2.wav`.
- paw replaces a file in `renders/` without a question. To replace a file
  in another folder, press `y` in the plan or type `:export!`.

### The plan

Before an export of more than one file, or one that replaces a file
outside `renders/`, paw shows the plan in a float. The plan lists each
file with what it holds, when, its tap and its channels. Below the files,
it names the muted tracks that it leaves out, and it says when a
compressor, limiter or gate on a group or on the master makes the files
differ a little from the mix.

| Key | Effect |
| --- | --- |
| `y`, `Enter` | write the files |
| `n`, `Esc` | close the plan, and write nothing |
| `j`, `k` | scroll |

A range of only muted tracks writes nothing, and the message says so.

### Progress and the result

The files render one at a time, in one queue. The status line shows
`exporting 3/12 Bass.wav 43% · Esc cancels`. `Esc` in normal mode, or
`:export.cancel`, stops the whole queue. At the end, one message names the
files, their length and the peak, for example `wrote 2 files to
renders/stems (3:21 each, peak -0.8 dB)`. `:messages` keeps it.

### Keys

| Keys | Effect |
| --- | --- |
| `<Space>em` | `:export`, the mix |
| `<Space>es` | `:export stems` |
| `<Space>et` | `:export tracks` |
| `<Space>er` | `:export regions` |
| `<Space>ee` | the last export again |

In visual mode, `<Space>em`, `<Space>es`, `<Space>et` and `<Space>er`
export the tracks and the time of the selection.

### Lua

| Function | Result |
| --- | --- |
| `paw.export.plan(words, range)` | The plan of `:export` with these words: `{ renders, left_out, notes, confirm }`. Each render has its `file`, `tracks`, `from`, `to`, `when`, `tap` and `channels`. `range` is `paw.ex.range("t2,t4 5,8")`, or nil. |
| `paw.export.run(plan)` | Write the files of a plan. |
| `paw.export.last()` | What the last export wrote: `{ results, failed, cancelled, message }`. |
| `paw.export.cancel()` | Stop the export. |

## `:render`

`:render mix.flac` renders the song to a file. The extension of the file
sets the format. With no name, the file is `<project>.wav` in the folder
`renders` of the project (see [The renders folder](#the-renders-folder)).

- The render runs on a thread of its own, and the status line shows
  `rendering mix.flac 43% · Esc cancels` while it runs. A message tells when the render
  is complete.
- `Esc` in normal mode, or `:render.cancel`, stops the render.
- The render plays a copy of the project made when it starts, so an edit
  during the render changes the project and not the file.
- paw writes the file as `.mix.flac.part` next to the target and gives it
  its name when it is complete, so a render that fails or that you cancel
  leaves no file with that name.

### The renders folder

A render with no name goes into `renders` in the folder of the project:
`song/renders/song.wav`, and the stems in `song/renders/stems`. paw makes
the folder at the first render and keeps the rendered files apart
from the files of the project, so a save never moves them to `unused`. To
keep them out of git, add `renders/` to a `.gitignore` file.

- A project in one JSON file renders next to its file.
- Before the first save, paw renders into the folder where it started.
- A name without a folder (`:render mix.flac`) goes into the folder of the
  project, or into the folder that `:cd` set.

### Options

The options are words after the file name, and `<Tab>` completes them.

| Option | Values |
| --- | --- |
| `range=` | `song`, `loop`, `selection`, or the name of a region, or its path when names repeat: `Chorus 2/Verse A` (see [Markers and regions](markers.md)) |
| `start=`, `end=` | the range in beats |
| `tail=2` | seconds after the end, for reverbs (default: 1) |
| `rate=44100` | the sample rate |
| `bits=` | `16`, `24` (default) or `32` (float, WAV only) |
| `channels=` | `stereo` (default), `mono` or `auto` (see [Mono and stereo](#mono-and-stereo)) |
| `quality=` | `low`, `medium`, `high` (default) or `best` (MP3, Ogg and Opus) |
| `bitrate=192` | kbit/s, instead of `quality` (MP3, Ogg and Opus) |
| `dither=true` | dither |
| `normalize=-1` | the peak level in dB |
| `loudness=-14` | the integrated loudness in LUFS, measured as BS.1770. With `normalize` too, the peak level is a ceiling. |
| `tracks=` | `selected`, or `3,5`: a stem of those tracks |
| `master=false` | without the devices, fader and pan of the master |
| `stems=true` | one file for each track, into a directory |
| `wait=true` | render in the foreground |
| `artist=` and the other tags | tags for this file only (see Tags) |

`:stems out format=flac master=false` also renders stems.

For normalization, paw renders the song once into a temporary file,
measures it, and encodes from there.

### Formats

| Format | Extension | Encoder |
| --- | --- | --- |
| WAV | `.wav` | paw |
| FLAC | `.flac` | paw |
| MP3 | `.mp3` | `ffmpeg` |
| Ogg Vorbis | `.ogg` | `ffmpeg` |
| Opus | `.opus` | `ffmpeg` |

- paw refuses formats that need an encoder that it does not have (AAC,
  AIFF, WMA) by name, before it renders anything.
- `paw.api.render_formats()` lists the formats that paw can write:
  `{ name, extensions, bits, lossy, available, why }`.

### MP3, Ogg Vorbis and Opus

paw has no encoder for these formats, so it uses `ffmpeg` if it is
installed.

- paw renders the song to a hidden 32-bit float WAV next to the target (no
  dither, at the requested sample rate). `ffmpeg` encodes it into a `.part`
  file, and paw gives the file its name when it is complete. paw removes
  the WAV after the encode, even when the encode fails or you cancel it.
- The encode runs on the thread of the render. The status line shows
  `encoding mix.mp3 61%` (the graphical window shows "Encoding"). `Esc` or
  `:render.cancel` also stops `ffmpeg`.
- Opus holds only 48 kHz and the lower usual rates, so `ffmpeg` converts to
  48 kHz, and it also converts MP3 above 48 kHz to 48 kHz.
- `ffmpeg` is the program on the PATH. `paw.opt.ffmpeg = "/path/to/ffmpeg"`
  names a different program.
- Without `ffmpeg`, or with an `ffmpeg` without the encoder,
  `:render mix.mp3` fails before it renders anything, and the message says why
  and names the formats that need nothing (WAV and FLAC).
  `render_formats()` then gives `available = false` and `why`, and the
  render dialog of the graphical window does not offer the format.

| `quality` | MP3 (`LAME`) | Ogg Vorbis | Opus |
|---|---|---|---|
| `low` | VBR `-q:a 6` (about 115 kbit/s) | `-q:a 3` | 64 kbit/s |
| `medium` | VBR `-q:a 4` (about 165) | `-q:a 5` | 96 kbit/s |
| `high` | VBR `-q:a 2` (about 190) | `-q:a 7` | 128 kbit/s |
| `best` | constant 320 kbit/s | `-q:a 9` | 192 kbit/s |

A `bitrate` is constant for MP3, and the target for Opus and Vorbis.
`bits=` and `dither=` do not apply to these formats.

## Tags

A rendered file has a title, artist, album, track number, year, genre,
comment and cover picture, when they are set. The tags belong to the
project, which keeps them for each render (`project.meta.tags`, saved with
it).

```
:render.tags artist=Ana album="First one" track=3/12 year=2026 genre=Ambient comment="a note" cover=cover.png
:render.tags                  " what is set
:render.tags genre=           " an empty value takes one out
```

- In Lua, `paw.render_tags()` gives the table, and
  `paw.render_tags({ artist = "Ana" })` sets those fields and keeps the
  others.
- `:render` accepts the same words (`:render mix.mp3 artist=Bo`), and
  `paw.render` accepts a `tags` table, for that file only, and either one
  replaces the tags of the project for that file.
- The title of an MP3, Ogg or Opus file is the name of the project, unless
  you give one. The title of a stem in these formats is the name of its
  track.
- A relative `cover` path starts at the directory of the project. The
  cover is a PNG or JPEG file of 8 MiB at most, and if paw cannot read it, it
  refuses the render before it renders anything.
- The render dialog of the graphical window has the tags under Tags. What
  you type there becomes the tags of the project.

| Format | Where the tags go |
| --- | --- |
| WAV | a `LIST` chunk of `INFO` (`INAM`, `IART`, `IPRD`, `ITRK`, `ICRD`, `IGNR`, `ICMT`). No cover, because players do not read one in a WAV. |
| FLAC | Vorbis comments and a `PICTURE` block |
| MP3 | ID3v2.3, with the cover as an attached picture |
| Ogg Vorbis, Opus | Vorbis comments, with the cover in `METADATA_BLOCK_PICTURE` |

`ffmpeg` writes the tags of the last three formats, and paw gives it the tags
in a file and not on its command line.

## Mono and stereo

paw mixes in stereo, and `channels=` says how many channels the file has.

| `channels=` | The file |
| --- | --- |
| `stereo` | Two channels, as you hear the song. This is the default. |
| `mono` | One channel, the sum of the two sides at half level each: (left + right) / 2. |
| `auto` | One channel when the two sides are the same in each sample of the file, and two channels when they differ. |

A sound that is the same on both sides, such as a mono recording panned to
the center, keeps its level in a mono file. Where the sides differ, the
mono file is quieter, and sound that is in opposite phase on the two sides
cancels out. A mono render of the song is how it sounds on a mono speaker.

The pan stays in the sound. paw pans with equal power, so a mono source
panned hard left is 3 dB louder on the left than in the center and silent
on the right, and its mono file is 3 dB quieter than in the center. To
render a track without its pan, render it with `tap=pre`.

`auto` looks at the rendered sound, not at the files on the track. A mono
recording in the center gives a mono file. The same recording panned off
center, or through a stereo device such as a reverb, gives a stereo file.
The result of the render says how many channels the file has.

## Lua

`paw.render(path, opts)` accepts the options as a table. The fields are
`range`, `start`, `end`, `tail`, `sample_rate` or `rate`, `bits`,
`channels` (`"stereo"`, `"mono"`, `"auto"`), `quality`, `bitrate`, `ffmpeg`,
`dither`, `normalize`, `loudness`, `tracks = { id, ... }`, `tap`, `master`,
`threads`, `sleep`, `tags` and `freeze`.

`tap` is the point in the sound of the tracks where the render listens.
Each point holds all the points before it.

| `tap` | The file holds |
| --- | --- |
| `"pre"` | the clips and devices of the tracks, and of the tracks inside them, without the fader, pan or mute |
| `"post"` | the clips and devices with the fader, pan and mute, but not the groups, the sends or the master |
| `"groups"` | the tracks as you hear them when they are soloed, through their groups and the returns of their sends, but not the master |
| `"master"` | the same as `"groups"`, and then the devices, fader and pan of the master. This is the default. |

`"pre"` and `"post"` need `tracks`. Files rendered at `"groups"` or at
`"master"` add up to the mix at that point. `master = false` is the same as
`tap = "groups"`.

- `sleep = false` makes each device run on each block, even when it is at
  rest (see [The audio engine](engine.md#devices-at-rest)), and the file is
  the same to the bit.

- It waits for the file, and returns `{ path, frames, seconds,
  sample_rate, peak, gain, loudness, format, bits, channels, ... }`.
- With `background = true`, it returns immediately and events follow.

| Event | Contents |
| --- | --- |
| `render.progress` | `{ path, fraction, seconds, stage }`, some times each second. `stage` is `"rendering"` or `"encoding"`. |
| `render.done` | the table above, one time, for the final file |
| `render.failed` | `{ path, error }` |
| `render.cancelled` | |
| `render.finished` | a render in the foreground is complete |

| Function | Result |
| --- | --- |
| `paw.render(path, opts)` | Render a file with the options above. |
| `paw.render_status()` | The render that runs: `{ path, fraction, seconds, cancelling, stage, queued }`. |
| `paw.render_cancel()` | Stop it. |
| `paw.render_ranges.chorus = function() return 32, 48 end` | Add a named range. |

The graphical window finds the render in `paw.frontend.state().modal.render`.

## Stems

`:export each=track` writes one file for each track. The files add
up to the mix exactly through sends, returns and buses that only filter,
delay or mix. A compressor or a limiter on a shared bus hears each stem
alone and acts on a stem differently than on the sum, so with those the files
differ a little from the mix.

`:render stems` writes one file for each group, with the name of the
group, into `renders/stems`:

- each group at the top level, and each track outside a group that has
  clips, each with all that its sound goes through, so these files also
  add up to the mix.
- First, paw shows the plan, which lists each file and its tracks. `y` or `Enter`
  renders, and `n` or `Esc` cancels.

| Command | Effect |
| --- | --- |
| `:render stems` | One file for each group, into `renders/stems`. |
| `:render stems out` | The same, into `out`. |
| `:render stems tracks` | One file for each track. |
| `:render Strings` | One group, to `renders/Strings.wav`, with no plan. |

- In a window narrowed to a group, `:render stems` writes the parts of its group.
- The options of `:render` apply (`format=flac`, `tail=`, `bits=`,
  `master=false`, and the others).
- In Lua, `paw.export.plan("stems")` gives the plan, and
  `paw.export.run(plan)` writes it.

## Bounce

`:bounce` renders the track at the cursor to audio, as one clip on a new
track below it, and mutes the old track. The new track plays into the same
track as the old one, and the message names it. One `u` undoes the bounce.

A bounce of a range of time mutes only that time, and the old tracks go on
playing outside it. paw cuts each clip that crosses an edge of the range,
and mutes the parts inside the range. The new clip starts where the range
starts, right below the muted parts, and it holds the tail after the range
too. A muted clip shows `⊘` before its name and a faint body, and `K` on a
muted part names the track that now plays it. One `u` puts the clips back
whole.

Notes that cross an edge of the range play whole in the new clip, so the
song sounds the same. A note that starts in the range rings on to its end.
A note that starts before the range and is still held at its start moves
to the new clip, which then starts where that note starts.

| Command | Effect |
| --- | --- |
| `:bounce`, `<Space>tb` | Bounce the track at the cursor. In visual mode, `<Space>tb` bounces the selected tracks. |
| `:t2,t4bounce`, `:t'<,'>bounce` | Bounce those tracks to one new track, and mute each of them. |
| `:5,8bounce`, `:'<,'>bounce` | Bounce bars 5 to 8, or the time of the selection, and mute only those bars of the old track. |
| `:bounce tap=pre` | Bounce before the fader (see below). |
| `:bounce tail=4` | Render 4 seconds after the end (default: 2). |

`tap=` is where the render listens (see [Lua](#lua)):

- `tap=post` is the default. The file has the devices, fader and pan of
  each track, but not its groups or the master. The new track starts at 0
  dB in the center, so the song sounds the same through the groups and the
  master.
- `tap=pre` renders before the fader. The new track gets the volume, pan
  and sends of the old track, and the automation of its volume and pan, so
  the fader stays live. It takes one track.

In Lua, `paw.bounce(track, { tap = "pre", tail = 2, name = "Pad" })`
bounces one track, and `paw.bounce.tracks({ id, ... }, opts)` bounces
several. With `start` and `end` in beats, they bounce that time only. Both
return the new track.

## Regions

`:render.regions out` writes each region to a file of its own (see
[Markers and regions](markers.md)). A region inside another region has
the path in its file name: `02 Chorus 2 - 01 Verse A.wav`. `level=1`
renders only the regions at the top level, and `level=leaves` only the
regions with no region inside.

## Behavior

- Stems and bounces go through `paw.render`, so the hook `render.before`
  runs for them.
- A render, an export, stems, a bounce and a freeze always play the
  built-in devices at full quality, whatever `paw.opt.quality` says (see
  [Edit quality](engine.md#edit-quality)). A file rendered while paw plays
  in edit quality is the same to the bit as one rendered at full quality.
- paw tells plugins when a render is offline, and gives them time to
  prepare before it starts, because many plugins load the data of a setting in the
  background and would still be silent at the end of a fast render.
- A render waits for devices with the status `loading` (see
  [Plugins](plugins.md#load-in-the-background)).
- Language servers can get each render as a subject, so a delivery or
  settings check can look at each render and show diagnostics with
  fixes. A server of the mix gets the fader, pan, sends and devices of each
  track. See [Language servers and diagnostics](language-servers.md).

### Plugins in a render

A render, an export, stems and a freeze each make their own copy of every
plugin, and paw tells each copy that the render is offline before the copy
plays its first block. A plugin that has its own quality setting for renders
can then use that setting. The plugins that play live are not told, so they
stay in their live mode.

| Format | What paw tells a plugin in a render |
| --- | --- |
| CLAP | paw sets the `clap.render` extension to offline. A plugin without the extension gets no call. |
| VST3 | paw calls `setupProcessing` with the process mode `kOffline`, and stops the plugin for the call and starts it again after. |
| LV2 | LV2 has no call for the render mode. paw sets the plugin's free-wheeling port to 1 if the plugin has one, and after each block it waits for the jobs that the plugin runs in the background. |

A plugin in a helper process (see [Processes](plugins.md#processes)) gets
the same call in that process.
