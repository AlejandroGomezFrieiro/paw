# Render

<!-- tags: render rendering export stems bounce render-tags -->

A render writes the song, a part of it, or its tracks to sound files. For
the steps, see [How to export a song as WAV, FLAC or MP3](../how-to/export-a-song.md) and
[How to render stems](../how-to/render-stems.md).

## Commands

| Command | Effect |
| --- | --- |
| `:render mix.flac` | Render the song to a file (see below). |
| `:render.cancel` | Stop the render. |
| `:render.tags` | Show or set the tags of the project (see Tags). |
| `:render stems` | Render one file for each group (see Stems). |
| `:render.regions out` | Render each region to a file of its own (see Regions). |
| `:stems out` | Render one file for each track into `out` (default: `renders/stems`), as `paw.render_stems`. |
| `:track.bounce` | Render a track to a new audio track (see Bounce). |

## `:render`

`:render mix.flac` renders the song to a file. The extension of the file
sets the format. With no name, the file is `<project>.wav` in the folder
`renders` of the project (see [The renders folder](#the-renders-folder)).

- The render runs on a thread of its own. The status line shows
  `rendering mix.flac 43% · Esc cancels`. A message tells when the render
  is complete.
- `Esc` in normal mode, or `:render.cancel`, stops the render.
- The render plays a copy of the project made when it starts. An edit
  during the render changes the project, not the file.
- paw writes the file as `.mix.flac.part` next to the target, and gives it
  its name when it is complete. A render that fails or that you cancel
  leaves no file with that name.

### The renders folder

A render with no name goes into `renders` in the folder of the project:
`song/renders/song.wav`, and the stems in `song/renders/stems`. paw makes
the folder at the first render. The folder keeps the rendered files apart
from the files of the project, so a save never moves them to `unused`. To
keep them out of git, add `renders/` to a `.gitignore` file.

- A project in one JSON file renders next to its file.
- Before the first save, paw renders into the folder where it started.
- A name without a folder (`:render mix.flac`) goes into the folder of the
  project, or into the folder that `:cd` set.

### Options

The options are words after the file name. `<Tab>` completes them.

| Option | Values |
| --- | --- |
| `range=` | `song`, `loop`, `selection`, or the name of a region, or its path when names repeat: `Chorus 2/Verse A` (see [Markers and regions](markers.md)) |
| `start=`, `end=` | the range in beats |
| `tail=2` | seconds after the end, for reverbs (default: 1) |
| `rate=44100` | the sample rate |
| `bits=` | `16`, `24` (default) or `32` (float, WAV only) |
| `channels=` | `mono` or `stereo`. Mono mixes the two sides at half level each. |
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

For normalization, paw renders the song one time into a temporary file,
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
  AIFF, WMA), by name, before it renders anything.
- `paw.api.render_formats()` lists the formats that paw can write:
  `{ name, extensions, bits, lossy, available, why }`.

### MP3, Ogg Vorbis and Opus

paw has no encoder for these formats. It uses `ffmpeg`, if it is
installed.

- paw renders the song to a hidden 32-bit float WAV next to the target (no
  dither, at the requested sample rate). `ffmpeg` encodes it into a `.part`
  file, and paw gives the file its name when it is complete. paw removes
  the WAV after the encode, also when the encode fails or you cancel it.
- The encode runs on the thread of the render. The status line shows
  `encoding mix.mp3 61%` (the graphical window shows "Encoding"). `Esc` or
  `:render.cancel` also stops `ffmpeg`.
- Opus holds only 48 kHz and lower usual rates, so `ffmpeg` converts to
  48 kHz. MP3 above 48 kHz is also converted to 48 kHz.
- `ffmpeg` is the program on the PATH. `paw.opt.ffmpeg = "/path/to/ffmpeg"`
  names a different program.
- Without `ffmpeg`, or with an `ffmpeg` without the encoder,
  `:render mix.mp3` fails before it renders anything. The message says why,
  and names the formats that need nothing (WAV and FLAC).
  `render_formats()` then gives `available = false` and `why`, and the
  render dialog of the graphical window does not offer the format.

| `quality` | MP3 (LAME) | Ogg Vorbis | Opus |
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
  `paw.render` a `tags` table, for that file only. They replace the tags
  of the project for that file.
- The title of an MP3, Ogg or Opus file is the name of the project, unless
  you give one. The title of a stem in these formats is the name of its
  track.
- A relative `cover` path starts at the directory of the project. The
  cover is a PNG or JPEG file of 8 MiB at most. If paw cannot read it, it
  refuses the render before it renders anything.
- The render dialog of the graphical window has the tags under Tags. What
  you type there becomes the tags of the project.

| Format | Where the tags go |
| --- | --- |
| WAV | a `LIST` chunk of `INFO` (`INAM`, `IART`, `IPRD`, `ITRK`, `ICRD`, `IGNR`, `ICMT`). No cover, because players do not read one in a WAV. |
| FLAC | Vorbis comments and a `PICTURE` block |
| MP3 | ID3v2.3, with the cover as an attached picture |
| Ogg Vorbis, Opus | Vorbis comments, with the cover in `METADATA_BLOCK_PICTURE` |

`ffmpeg` writes the tags of the last three formats. paw gives it the tags
in a file, not on its command line.

## Lua

`paw.render(path, opts)` accepts the options as a table. The fields are
`range`, `start`, `end`, `tail`, `sample_rate` or `rate`, `bits`,
`channels` (1, 2, `"mono"`, `"stereo"`), `quality`, `bitrate`, `ffmpeg`,
`dither`, `normalize`, `loudness`, `tracks = { id, ... }`, `master`,
`threads`, `sleep`, `tags` and `freeze`.

- `sleep = false` makes each device run on each block, also when it is at
  rest (see [The audio engine](engine.md#devices-at-rest)). The file is
  the same to the bit.

- It waits for the file, and returns `{ path, frames, seconds,
  sample_rate, peak, gain, loudness, format, bits, channels, ... }`.
- With `background = true`, it returns immediately, and events follow.

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
| `paw.render_stems(dir, opts)` | Write one file for each track. |

The graphical window finds the render in `paw.frontend.state().modal.render`.

## Stems

`paw.render_stems(dir, opts)` writes one file for each track. The files add
up to the mix exactly through sends, returns and buses that only filter,
delay or mix. A compressor or a limiter on a shared bus hears each stem
alone. It acts on a stem differently than on the sum, so there the files
are a little different.

`:render stems` writes one file for each group, with the name of the
group, into `renders/stems`:

- each group at the top level, and each track outside a group that has
  clips, each with all that its sound goes through. So these files also
  add up to the mix.
- First, paw shows the plan: each file and its tracks. `y` or `Enter`
  renders. `n` or `Esc` cancels.

| Command | Effect |
| --- | --- |
| `:render stems` | One file for each group, into `renders/stems`. |
| `:render stems out` | The same, into `out`. |
| `:render stems tracks` | One file for each track. |
| `:render Strings` | One group, to `renders/Strings.wav`. |

- In a narrowed tab, `:render stems` writes the parts of its group.
- The options of `:render` apply (`format=flac`, `tail=`, `bits=`,
  `master=false`, and the others).
- In Lua, `paw.stems.plan({ dir, format, tracks, group })` gives the list
  (`{ id, name, file, holds }`), and `paw.stems.render(plan, opts)` writes
  it.

## Bounce

`:track.bounce` renders a track with its devices to audio, on a new track,
and mutes the original track. In Lua: `paw.bounce(track, { name = ... })`,
which returns the new track.

## Regions

`:render.regions out` writes each region to a file of its own (see
[Markers and regions](markers.md)). A region inside another region has
the path in its file name: `02 Chorus 2 - 01 Verse A.wav`. `level=1`
renders only the regions at the top level, and `level=leaves` only the
regions with no region inside.

## Behavior

- Stems and bounces go through `paw.render`, so the hook `render.before`
  runs for them.
- paw tells plugins when a render is offline, and gives them a moment to
  prepare before it starts. Many plugins load the data of a setting in the
  background, and would still be silent at the end of a fast render.
- A render waits for devices with the status `loading` (see
  [Plugins](plugins.md#load-in-the-background)).
- Language servers can get each render as a subject. A delivery or
  settings check can then look at each render and show diagnostics with
  fixes. A server of the mix gets the fader, pan, sends and devices of each
  track. See [Language servers and diagnostics](language-servers.md).
