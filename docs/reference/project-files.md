# Project files

<!-- tags: saving safety-copies recover autosave project-file project-folder midi2 collect on_external_change -->

A project is a folder of files, and the sections below describe those files, how paw saves them, how it keeps safety
copies, and how it recovers work. For why paw saves this way, see
[About project files](../explanation/about-project-files.md). For the
steps, see [How to recover lost work](../how-to/recover-lost-work.md).

## The project folder

```text
song/
├── project.toml            name, tempo, meter, tempo map, key, order of the tracks, subprojects, transport
├── meta.json               the data of extensions (`paw.project.meta`), if there is some
├── screen.json             the tabs and windows that the project opens with
├── media.json              the hash, size and format of each file that the clips play
├── .gitattributes          *.midi2 diff=paw-midi2
├── master/                 the master track, as a track folder
├── tracks/
│   └── Keys/               one folder for each track, with the name of the track
│       ├── track.json      the track and its clips, without the notes
│       ├── devices.json    the chain and its parameters
│       ├── 1-synth.state   the state of a plugin, as the plugin gives it
│       ├── 2-clap-….ara    a file of an attachment, beside the state (the ARA archive)
│       ├── automation/volume.json
│       ├── clips/riff.midi2
│       ├── clips/take.edits.json  the edit list of an audio clip, if it has one
│       ├── clips/intro.video.json   the data of a custom clip of the kind `video`
│       ├── clips/intro.signals.json the signals of a custom clip, if it has some
│       ├── clips/intro.sound.midi2  the sound of a custom clip, if it is MIDI
│       └── clips/verse.lyrics.lrc   the data of a custom clip that is text
├── media/take1.wav         sound files
│   └── derived/            files that a kind of clip makes from other files
├── nests/
│   └── Bridge/             one folder for each subproject that the song plays
│       ├── nest.toml       its id, name, length, tempo, meter and the order of its tracks
│       ├── meta.json       its markers and the data of extensions, if there is some
│       ├── master/         its master track, as a track folder
│       └── tracks/Piano/   its tracks, as track folders
├── renders/                the files that a render with no name writes (not saved, never moved)
└── unused/                 files that the project does not use now
    └── nests/Bridge/       a subproject that no clip of the song places
```

- The project's file is `song/project.toml`. `:e song`, `:open song`
  and `paw song` open the folder.
- A track folder and a clip file have the name of the track and of the
  clip. Letters, digits, `-`, `_` and `.` stay as they are, and paw changes
  other characters to `-`. Two of the same name get `-2`, `-3`.
- An automation file has the name of what it automates: `volume.json`
  or `pan.json`, or the device and the parameter, as in `1-synth-wave.json`.
- The JSON files have their keys in alphabetical order.
- `track.json` names each clip file by its path in the folder. It names a
  file outside the folder by its full path, or from the home folder as
  `~/…`.
- Clips with the same notes, controller moves and length share one file.
- A custom clip is a clip of a kind that an extension defines. `track.json`
  keeps its kind, its version, its timeline, its offset, its media and the
  names of its files. Its data is a file of its own:
  `<clip>.<kind>.json` for a value and `<clip>.<kind>.<ext>` for text.
  - The kind gives its data as a value: tables, strings, numbers and
    booleans. paw writes the value as JSON on lines, with the keys in
    alphabetical order, so a change of one field is one line in
    `git diff`, and a value that does not change keeps the same bytes.
  - The kind gives text data in its own format, for example `.lrc`. paw
    writes the text with no change. The text is UTF-8.
  - paw does not accept binary data or data over 1 MB in a clip. Put such
    data in a media file of the clip.

  Its signals are `<clip>.signals.json`, and the body of a signal is JSON
  in that file. Its sound is `<clip>.sound.midi2` when it is MIDI, and a
  media file when it is audio. Clips with the same data share one data
  file, as the two halves of a split clip do.
- paw opens a custom clip of a kind that no extension defines now, and
  saves it again with the same bytes. A data file that is missing, or that
  is not JSON, makes `:e` fail with the name of the file and the line and
  column of the error.
- `media.json` has one entry for each media file that the project uses,
  sorted by the path that the clips give: the BLAKE3 hash of its bytes
  (`b3:` and 64 hexadecimal digits), its size in bytes, and its streams
  (rate, channels and frames of the sound). The hash tells what the file
  is, at any path. See [Media files](media.md#what-a-file-is).
- `.gitattributes` is written when the folder has none.

## Subprojects

A subproject is a set of tracks with a timeline of its own, which a clip
places in the song. In commands and in the files, a subproject is a
"nest". Each subproject that the song plays has a folder in `nests/`.

- `project.toml` lists the folders in `nests` in the order that the
  subprojects were made.
- `nest.toml` has the subproject's id, name and length in beats. It also
  has its tempo and meter (`follow` the song's, or `own`) and the list
  of its track folders in order.
- A track folder of a subproject is the same as a track folder of the
  song. A clip that places a subproject is a line in `track.json`, with
  the kind `nest`, the subproject's id and what it plays: `"master"` for
  the mix, or `{ "track": id }` for one track.
- The folders are all in `nests/`, also for a subproject inside another
  subproject.
- At a save, a subproject that no clip of the song places goes to
  `unused/nests/`. paw does not open it again, and never deletes it. A
  folder there that has another subproject stays, and the new one gets
  `-2`.
- A subproject can be inside another one, at most 8 deep. paw does not
  open a project where a subproject is inside itself, and the message
  gives the path, for example `Bridge › Verse › Bridge`.
- The tracks of a subproject send, output and take side-chains only to
  and from tracks of the same subproject. Its master has no output and
  no sends, because it plays into the song through the clips that place
  the subproject.

## Save

| Command | Effect |
| --- | --- |
| `:w song` | Save the project as the folder `song`. |
| `:w song.json` | Also save the project as the folder `song`, and say so. |
| `:w` | In the piano roll: write the file of the clip. In the device panel: write the files of the chain. Also the `track.json` and `project.toml` if they changed. Elsewhere: write all the files. |
| `:wa`, `:wall` | Write all the files of the project. |
| `:ls` | Also list the files of the project. `+` marks a file that is different from the file on the disk. |

- paw writes only the files that are different from the files on the
  disk.
- paw writes each file next to its place, writes it to the disk, and
  renames it over the old file. It writes `project.toml` last.
- `:w` of a folder that has other files and no `project.toml` does not
  save, so name a folder inside it.
- A name alone goes beside the folder of the project: `:w take2` makes the
  folder `take2` next to `song`.
- paw keeps the `project.toml` before a save that changes it as
  `project.toml.bak`.
- A file that the project does not use now goes to `unused/` at the same
  path. A file that is there already stays, and the new one gets `-2`.
  paw never deletes a file from `unused/`.
- A file with the same bytes as a new file moves to the place of the new
  file (a renamed track).
- The project is saved when no file is different from the disk. An undo
  back to the saved state makes the files the same again.
- After a save of the whole project, paw writes the undo history to the
  undo file in the state directory, not in the folder. See
  [Files that paw keeps](state-files.md#the-undo-file).
- `:q` refuses to quit with changes that are not saved. `:q!` quits without
  them.

### A project in one JSON file

paw writes one JSON file only for its own copies: the safety copies, the
states of the undo history and `paw.api.project_file_text`. It opens such
a file, and a project that an earlier version of paw saved in one file.

- `:w` saves a project that you opened from `song.json` as the folder
  `song` beside it, and says so. `song.json` stays as it was.
- A script that calls `paw.project.save("song.json")` writes one file, and
  keeps the file before as `song.json.bak`. A `.bak` names media relative
  to the project, as the project does, so it opens with its media.

## MIDI clip files

A MIDI clip is a MIDI 2.0 Clip File (`SMF2CLIP`, M2-116-U).

- A beat has 61440 ticks. paw rounds the time of a note and of a
  controller move to a tick.
- Notes are MIDI 2.0 note-on and note-off messages with velocities of 16
  bits and their attribute. Controller moves are MIDI 2.0 messages with
  values of 32 bits.
- The `meta` of a note, its id (when the ids are not 1, 2, 3 in order),
  and the start of a note before the start of the clip are in Flex Data
  text that starts with `paw:`.
- End of Clip is at the length of the clip.
- paw also reads MIDI 1.0 messages in a clip file, and a file with a
  different number of ticks to a beat. It tells what it left out.
- paw keeps a velocity at 7 bits. A clip file from another program with
  velocities of 16 bits gets velocities of 7 bits in paw.

| Command or function | Effect |
| --- | --- |
| `paw clip cat riff.midi2` | Print the clip as text, one note or controller move on each line. |
| `:e riff.midi2`, `paw riff.midi2` | Open the clip alone, on a track with the synth, in the piano roll. `:w` writes it back to its file. |
| `:import riff.midi2` | Put the clip on the track of the cursor, at the cursor. The clip refers to the file. |
| `paw.api.midi2_read(path)` | `{ notes, controls, length, skipped }` of a clip file. |
| `paw.api.midi2_write(path, clip)` | Write `{ notes, controls, length }` as a clip file. |
| `paw.api.midi2_text(path)` | The text that `paw clip cat` prints. |

To show clip files as text in `git diff`, set the driver once:

```sh
git config --global diff.paw-midi2.textconv "paw clip cat"
```

## Files outside the folder

- A clip from a clip file outside the folder refers to the file:
  `paw.clip(id).source` is its path. A save keeps the path and writes no
  copy.
- The first edit of the notes makes them the project's own, in the same
  undo step. paw says so once:
  "riff is now this project's own copy (was ~/library/riff.midi2)".
  `paw.clip(id).origin` keeps the path, and `K` shows it.
- An undo of that edit makes the clip refer to the file again.
- A file that paw cannot find leaves the clip empty and offline. A save
  keeps its path.

A whole track and a chain of devices can also come from outside the
folder, with the same rules:

- A track folder (a folder with a `track.json`, for example
  `~/library/tracks/Lead` in a different project) gives a track that
  refers to the folder. `project.toml` names the folder in its list of
  tracks, and a save writes nothing of the track. Its clips refer to
  their files in the same way.
- A chain file (a `devices.json`, with the `.state` files beside it)
  gives the devices of a track that refers to the file. `track.json`
  names the file as `devices_file`, and a save writes no `devices.json`.
- The first edit of the track, or of the chain, makes it the project's
  own, and paw says so once: "the track Lead is now this
  project's own copy (was ~/library/tracks/Lead)". A track takes its
  clips from that folder with it.
- A part from outside keeps its ids, and gets new ones only where the
  project has them. A track from outside plays into the master, with no
  sends.
- `K` (`:info`) shows the folder or the file, and where a copy came from.

| Command | Effect |
| --- | --- |
| `:import ~/library/tracks/Lead` | Add the track of a track folder below the track of the cursor. The track refers to the folder. |
| `:import ~/chains/amp/devices.json` | Give the track of the cursor the devices of a chain file, in place of its devices. The track refers to the file. |
| `:e devices.json`, `paw devices.json` | Open a chain file alone, on a track of its own, in the device panel. `:w` writes it back. |
| `:collect` | Make every track, chain and clip from outside the project's own, and copy every sound file from outside into `media`. The next save writes their files into the folder. |
| `paw.api.track_import_folder(folder, index)` | Add the track of a track folder, as `:import` does. |
| `paw.api.track_chain_file(track, file, refer)` | Give a track the devices of a chain file. Without `refer`, they are the track's own at once. |
| `paw.api.chain_write(track, file)` | Write the devices of a track as a chain file. |

## Changes from outside paw

paw watches the folders of a project folder, and the folders of the files
outside it that the project uses. A save by paw is not a change, and changes
that happen close together (a `git checkout`) count as one change. paw acts
when you come back to it, which is when its terminal or its window gets the
focus of the desktop, or on the next key in a terminal that does not report
the focus (mode 1004). paw acts as `paw.opt.on_external_change` says:

| Value | Effect |
| --- | --- |
| `"ask"` (default) | Ask: `y` reads the files again, another key keeps the version of paw. |
| `"reload"` | Read the files again when the project has no changes that are not saved. Else ask. |
| `"keep"` | Keep the version of paw, and say so. The next save writes over the files. |

- To read the files again is one undo step. The parts that did not change
  keep their plugins.

| Function | Effect |
| --- | --- |
| `paw.api.project_changed_files()` | The files that changed outside paw, not acted on yet. |
| `paw.api.project_reload()` | Read the project folder again, as one undo step. |
| `paw.api.project_keep_changes()` | Keep the version of paw. |
| `paw.api.project_files()` | Each file of a project folder: `{ path, modified, what, track, clip }`. |
| `paw.api.project_save_files(paths)` | Write these files, and the files that they name that are not on the disk. |

## A second paw on the same project

When a paw on this computer already has `song` open, `paw song` does not open a
second copy. The terminal joins the running paw as a new seat, as
`paw attach` does (see [About seats](../explanation/about-seats.md)). `:detach` leaves.

## Same bytes on each save

When paw writes a project as one JSON file, it writes the fields in the order of the model
and sorts the maps by key. Each number has the fewest digits that read back exactly. A save of a project with no change therefore writes the same bytes, and
one change gives a small diff.

| Function | Result |
| --- | --- |
| `paw.api.project_file_text(file)` | The text of a project given as data, written the same way. It refuses a project that would not open. |
| `paw.api.undo_project(id)` | A state of the undo tree, as a project file holds it. |

`extensions/projdiff` uses both: a diff and a three-way merge of projects,
and the drivers for version control.

## Safety copies

| Option | Default | Effect |
| --- | --- | --- |
| `paw.opt.autosave` | `60` (`0` with `--clean`) | Seconds between safety copies. 0: no copies. |

- Every `paw.opt.autosave` seconds, paw copies a project with changes that
  are not saved to `~/.local/state/paw/recovery`.
- paw removes the copy when you save the project, or close it with no
  changes.
- A copy that a session left after a bad end shows at the next start.
  `:recover` opens it, with the name of the project that it is a copy of.
- A panic writes a safety copy before paw stops, and says where the copy
  is (see [The audio engine](engine.md#a-device-that-fails)).
- A take is in the safety copy from its start (see
  [Recording](recording.md#files)).

## Damaged projects

If a project does not open (it is cut short, or damaged), the message
tells what can replace it. `:recover` lists its newest safety copy and its
`.bak` first. For a project folder, the `.bak` is `project.toml.bak`: paw
opens it with the other files of the folder. Each opens with the name of the damaged project and unsaved,
so `:w` puts it back. If you start paw with such a project on the command
line, paw starts and shows that message.

## `:recover`

| Command | Effect |
| --- | --- |
| `:recover` | List the safety copies, the `.bak` files of a damaged project, and takes that no clip uses. Select one to open or add it. |
| `:recover 1` | Open entry 1. |
| `:recover 1 offline` | Open entry 1 with its plugins offline (see [Plugins](plugins.md#offline-devices)). |

## Scripts

| Function | Effect |
| --- | --- |
| `paw.api.project_shelve()` | Put the open project aside, complete (undo tree, playhead, changed flag), and open an empty project. |
| `paw.api.project_unshelve()` | Close that project and bring back the first project as it was. |
| `paw.api.project_shelved()` | True if a project is aside. |

The shelf is for tools that need their own tracks without changing the
person's work. The [doctor](../../extensions/doctor) extension uses
it.

The suite runs `tests/*.lua` and `extensions/*/tests*.lua`, and gives each
the helpers of the suite.
