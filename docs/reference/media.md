# Media files and audio clips

<!-- tags: media media-files relink offline-clips audio-clips fades -->

The sound files of a project are its media. This page describes how a
project finds its files, how paw reads them, and the operations on audio
clips. For the steps to find lost files, see
[How to relink lost media](../how-to/relink-missing-media.md).

## Paths

- A saved project names the sound files inside its folder by a path
  relative to the project file. It names other files by their full path.
  So you can move or copy a project folder.
- When a project opens and a file is not at its path, paw looks for it:
  1. relative to the project (the last parts of its old path),
  2. by name, in the folder tree of the project,
  3. in the directories where it found other lost files.
- A file found at a different place marks the project as changed. Then a
  save keeps the new place.
- paw reports the files that it cannot find in one message. Their clips
  stay in the project, silent, with `offline = true` in their state
  (`paw.clip(id).offline`, and in `paw.frontend.state`). Both frontends
  write "offline" before their names.
- A save keeps the path of a file that paw cannot find.
- Old projects with full paths open with no change.

## Commands

| Command | Effect |
| --- | --- |
| `:media.relink` | List the files that paw cannot find. Select one, then the file that it is now. paw then looks for the others next to it. Or select "Search a directory" and a directory. |
| `:media.relink <dir>` | Look for these files in a directory. |
| `:media.relink <old> <new>` | Point a file that paw cannot find to a new file. |
| `:media.missing` | List the files that paw cannot find. |
| `:media.collect` | Copy each file from outside the project folder into `media` next to the project, and point the clips to the copies. The original files stay. |

`paw.opt.copy_imports = true` makes each import copy its file into `media`
immediately.

| Function | Result |
| --- | --- |
| `paw.media.missing()` | The files that paw cannot find. |
| `paw.media.list()` | Each file: `{ path, missing, inside, on_disk }`. |
| `paw.media.relink(old, new)` | Point a file to a new file. |
| `paw.media.search(dir)` | Look for these files in a directory. |
| `paw.media.collect()` | Copy the files into `media`. |
| `paw.pick.file({ directory = true })` | Select a directory. |

Each change is one undo step. The event `media.missing` (`{ files, found
}`) comes after a project opens with files that paw did not find, or found
at a new place.

## Sample rates

paw converts a sound file at a different rate than the engine (or than a
render) one time, when it loads the file. The converter is a band-limited
windowed-sinc resampler (`rubato`, 256 taps). No frequency above the
Nyquist frequency of the new rate folds back, and a tone keeps its level
and position. A change of the engine rate converts again.

## Waveforms

paw keeps the waveform overview of each file in `~/.cache/paw/peaks`, by
the path, size and modification time of the file. So paw draws a long file
zoomed out from the overview after the first time, without a decode.

## Long files

A file whose decoded sound is larger than `paw.opt.media_stream` megabytes
(64: about three minutes of stereo at 48 kHz) does not stay in memory.

- paw decodes it one time into files in `~/.cache/paw/media` (and converts
  it there, if its rate is not the rate of the engine). paw maps these
  files into memory.
- The engine reads them as any other samples. The system reads the pages
  from the disk, and releases them when memory is low.
- The kernel asks for the next seconds before the playhead (and before the
  loop start). Then the audio thread does not wait for the disk.
- paw keeps the decoded sound between runs, by the identity of the file.
  So a recording of one hour opens immediately the second time.
- The cache stays within `paw.opt.media_cache` gigabytes (16). The files
  used least recently go first.
- `paw.media.list()` tells for each file if it is `on_disk`.
- `paw.opt.media_stream = 0` keeps all files in memory.
- Renders read the same files, and are the same to the bit.

## Fades

An audio clip has `fade_in` and `fade_out`, in beats.

| Way | Effect |
| --- | --- |
| `clip.fade_in = 1` | A fade-in of one beat. |
| `:clip.fade in=1 out=2`, `<Space>cf` | Set the fades of the clip. |
| `\fi`, `\fo` | In the arrange view: a fade-in up to the cursor, a fade-out from the cursor. A count gives the beats. |
| `:clip.crossfade 1` | Extend the clip under the start of the next clip by one beat, and fade the two across each other. |

An edge that cuts into a recording always gets a fade of three
milliseconds. Then splits and cuts of audio do not click.

## Operations on audio clips

| Command | Effect |
| --- | --- |
| `:clip.reverse` | Play the audio clip at the cursor backwards. A `reverse` goes into the edit list of the clip, and a second `:clip.reverse` takes it away. Its fades change ends. |
| `:clip.gain 1.2 1.3 -12` | A gain of -12 dB on a part of the clip, from 1.2 to 1.3 seconds of the clip, in its edit list. |
| `:clip.edits` | List the edit list of the clip. |
| `:clip.edits.clear` | Take away the edit list of the clip. It plays its file again. |
| `:clip.normalize -1` | Set the gain of the clip so that its loudest sample is at -1 dB. |
| `:clip.glue` | Join the clip and the audio clips that touch or overlap it on its track into one clip. The new clip plays a new file of what they played together (gains, fades and overlaps, without the devices of the track). |

No operation changes the original file. Each is one undo step.

| Function | Effect |
| --- | --- |
| `paw.media.reverse(clip)` | `:clip.reverse` |
| `paw.media.gain_part(clip, from, to, db)` | `:clip.gain` |
| `paw.media.pencil(clip, at, values, channel)` | Draw samples over the samples of the clip from `at` seconds of the clip (a pencil fix), in channel 0 or 1, or in both. |
| `paw.media.edits(clip)` | The edit list: `{ { kind = "reverse" }, { kind = "gain", from, to, db }, { kind = "pencil", at, channel, values } }`, in seconds of the sound. |
| `paw.media.clear_edits(clip)` | `:clip.edits.clear` |
| `paw.media.normalize(clip, level)` | `:clip.normalize` |
| `paw.media.glue(clip)`, `paw.media.glue({ a, b, c })` | `:clip.glue` |

### The edit list of an audio clip

An audio clip has two kinds of change that keep its file as it is:

- The settings of the clip: where it starts in the file and its length
  (a cut), its gain, its fades, and its stretch and pitch. The engine
  applies these as it plays.
- The edit list: play backwards, a gain on a part, and pencil fixes, in
  order. The clip plays a version of its file that paw makes with them,
  on a different thread, as it makes a stretched clip.

- paw keeps a large version in the cache (`paw.api.media_store`). The
  version comes again from the file and the list, so to delete the
  cache loses nothing.
- In a project folder, the edit list is the file of the clip:
  `tracks/<track>/clips/<clip>.edits.json`. `track.json` names it as
  `edits_file`.

For stretch, pitch and loops of clips, see
[Stretched and looped clips](stretch.md). For import, see
[Recording](recording.md#import-sound-files).
