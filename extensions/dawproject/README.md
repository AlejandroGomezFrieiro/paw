# dawproject: songs to and from other DAWs

Opens DAWproject files (`.dawproject`) in paw, and writes the projects of
paw as DAWproject files. Bitwig Studio, PreSonus Studio One and Steinberg
Cubase read and write this open format. So a song can move between paw
and these programs in both directions.

```lua
paw.ext.load("/path/to/paw/extensions/dawproject")   -- or link it into ~/.config/paw/extensions
```

## Try it

1. Type `:ext.load dawproject`.
2. Type `:e song.dawproject` with the path of a file that another DAW
   wrote. The tracks of the song appear in the arrange view.
3. Read the page that opens over them. It lists what paw could not bring
   across, by kind. If paw brought all of it, there is no page.
4. Type `:w copy.dawproject`. The message tells what paw wrote.
5. Open `copy.dawproject` in the other DAW. The tracks, the clips and the
   plugins are there.

## How to

### How to open a DAWproject file

Type `:e song.dawproject`. paw puts the audio files of the song in a
folder beside the file, `song media`.

### How to add the tracks of a DAWproject file to this project

Type `:dawproject.import song.dawproject merge=true`. The project keeps its
own tempo map and its own master.

### How to write a project for another DAW

Type `:w song.dawproject`. The file holds the audio files and the states
of the plugins. To keep the audio files outside the file, type
`:dawproject.export song.dawproject embed=false`. Then the file refers to
the audio files where they are.

## Reference

### Commands

| Command | Effect |
| --- | --- |
| `:dawproject.import song.dawproject` | replaces the project with the song of the file. `merge=true` adds its tracks to the current project |
| `:dawproject.export song.dawproject` | writes the project as a DAWproject file. `embed=false` refers to the audio files and does not copy them into the file |
| `:edit song.dawproject`, `:e song.dawproject` | the same as `dawproject.import`. Other files open as before |
| `:write song.dawproject`, `:w song.dawproject` | the same as `dawproject.export`. Other files save as before |

The extension has no keys of its own.

After an import or an export, a page lists what paw could not bring
across, grouped by kind. The message line tells how much came across.

```lua
local dp = require("dawproject")
local result = dp.import("song.dawproject", { merge = true, media_dir = "/path/for/the/audio" })
print(result.report:text())              -- or result.report:data() as tables
dp.export("out.dawproject", { embed = false }).report:empty()   -- true when paw wrote all of it
```

### The format

A DAWproject file is a ZIP archive. It holds `project.xml` (the song),
`metadata.xml` (the title and the artist), the states of the plugins and
the audio files. The official XML schemas are in `schema/`, with their
license (MIT, Bitwig).

The archive is read and written with the core's `paw.zip`, and the XML
with the extension's own module:

- `paw.zip.read(bytes)` gives the files of an archive. It reads files that
  are stored and files that are compressed (deflate).
- `paw.zip.write(entries)` makes an archive of stored files.
- `dp.xml.parse(text)` gives a tree of elements, `dp.xml.write(root)` the
  text.

### What comes across

paw writes times on the arrangement in beats. Audio clips play their
files in seconds.

| | DAWproject → paw | paw → DAWproject |
| --- | --- | --- |
| Tempo, time signature | The tempo and time signature of the transport, and the tempo and time signature automation (tempo points in beats or in seconds). A linear tempo point becomes a ramp. When merged into an open project, the project keeps its own map | The same |
| Tracks | Name, color, volume, pan, mute, solo. A track in a track goes into it (a folder). A channel with a destination plays into that track | The same. A track that goes into the track above it (or into a folder that it is in) is written inside that track |
| Sends | Level, before or after the fader | The same |
| Master | Volume, pan, mute, devices, automation | The same |
| MIDI clips | Notes with their velocity and MIDI channel (in `meta.channel` of the note). Controllers, pitch bend, channel and key pressure and program changes in the clip become the controller moves of the clip. Play start, loops, mute (a clip that is not enabled) and the name | The same |
| Audio clips | The file, the play start as the offset into the file, the fades, mute and the name. Two warp points give the speed. Audio in a clip of clips (as Bitwig Studio writes it) becomes one clip. Audio from the archive goes into a folder beside the file | The same. paw copies each audio file into the archive once |
| Automation | Volume and pan of the tracks and the master, and the parameters of the devices that came across. Points that hold (the default) and linear points | The same |
| Markers | Markers with their colors. A marker that paw wrote for a region becomes the region again | Markers. A region becomes a marker at its start, with its length in the comment |
| CLAP plugins | When installed here: the same plugin with its state | With their state (`plugins/*.clap-preset`) |
| VST3 plugins | When installed here (found by the class id, else by name and vendor): the same plugin with the state of its `.vstpreset` | With their state as a `.vstpreset` |
| LV2 plugins and the devices of paw | Only from a file that paw wrote: the same device with its parameters | As a device (an LV2 plugin) or a built-in device (`synth`, `gain` and the others) that only paw reads, with its parameters. paw lists them |
| Bypass | The `Enabled` switch of each device | The same |
| Other devices | VST2 and Audio Unit plugins, the built-in devices of other programs, and plugins that are not installed: a placeholder in `meta.dawproject_placeholders` of the track (`name`, `format`, `position`, `reason`, the XML and the state), reported | Placeholders return into the chain at their places, with their states |

### What does not come across

paw lists these after each import or export.

- **DAWproject → paw:**
  - note-off velocities, per-note expressions, and expressions other than
    MIDI controllers (gain, pan, transpose, timbre, formant)
  - warp points between the first and the last (paw stretches the clip
    evenly), loops of stretched audio, loops of clips that hold clips
  - crossfades, fades on MIDI clips, video
  - automation of mute and of send levels, automation points that are not
    real values
  - send pan, sends that are off
  - the clip launcher (scenes and their clips)
  - the master of the file, when merged
- **paw → DAWproject:**
  - the class id of a VST3 plugin that is not installed here and did not
    come from a DAWproject file (a DAW finds the plugin by its name)
  - the pitch of audio clips, warp markers, the tension of smooth curves
    (they become straight lines), automation lanes that are off (they are
    written as on)
  - registered, assignable and per-note controllers, the bank of program
    changes, note attributes (MIDI 2.0 articulations)
  - the loop of the transport, record arm, inputs and monitoring
  - clips in the slots of the clip launcher

For a parameter of a CLAP or VST3 plugin, `parameterID` holds the id
that the plugin itself gives the parameter. The `deviceID` of a VST3
plugin holds its class id. Ids of 2^31 and more become negative numbers,
because the schema has a signed 32-bit number there.

For a device of paw or an LV2 plugin, `parameterID` holds the place of
the parameter in the device (the first is 0).

When paw reads a file, it finds a parameter by the id of the plugin
first, then by its name. See
[Device parameters](../../docs/reference/device-parameters.md).

### Tests

The suite runs `tests.lua`. The fixture `fixtures/studio.dawproject` is a
song written by hand in the shape that Bitwig Studio writes, made with the
`zip` program (so its files are compressed). `fixtures/studio/` holds its
files. The tests cover:

- the XML reader and writer, and ZIP archives, stored and compressed
- an import of the fixture, checked track by track and clip by clip
- an export, then an import, of a project made with the API
- the XML of each export, checked against the official schemas with
  `xmllint` (in the dev shell)
- plugins (CLAP and VST3) with their states and automation, when the test
  plugins are installed
- the commands, and `:e` and `:w` on `.dawproject` files

Nobody opened the exported files in Bitwig Studio, Studio One or Cubase.
None of them runs on this computer. The schemas say that the files have
the correct form.
