# Attachments

<!-- tags: attachment paw_attach.h plugins.attach ara native device-files paw.clips -->

An attachment is a native library that an extension ships. paw offers it
each CLAP plugin that paw makes. An attachment that takes a plugin can use
the extensions of the plugin and answer calls to the device. It can read
sound files through paw, get the audio clips of the track, and keep a file
beside the state of the device. The [ara](../../extensions/ara/README.md) extension
is an attachment. For why paw has attachments, see
[About ARA plugins](../explanation/about-ara.md).

The interface is C, in `crates/paw-plugins/include/paw_attach.h`.

## Load

| Function | Effect |
| --- | --- |
| `paw.plugins.attach(path)` | Load the library at `path` for each plugin that paw makes from now on. Returns the name of the attachment, or nil and the reason. |
| `paw.plugins.attached` | The attachments loaded, by name: the path of each. |

- The library exports `paw_attachment_entry`, which returns a
  `paw_attachment`: its version (`PAW_ATTACH_ABI`, now 1), its name and
  three functions.
- paw loads the attachment into each process that hosts plugins: the
  program, and each helper that starts after the call.
- paw never unloads an attachment.
- Load the attachment before the project opens, so that the plugins of
  the project get it. An extension does this in its `init.lua`.

## The functions of an attachment

| Function | When |
| --- | --- |
| `attach(host, format, plugin)` | paw made a plugin: after its `init`, before its `activate`. `format` is `"clap"`, `plugin` is the `clap_plugin_t`. Return a handle to take the plugin, or NULL. |
| `call(handle, method, data, size, out, write)` | A call to the device. `write` adds to the answer. |
| `detach(handle)` | The device goes. The plugin is not active and is not processed again. |

All three run on the main thread of the process that hosts the plugin.

### What `call` returns

| Value | Meaning |
| --- | --- |
| `PAW_CALL_UNKNOWN` | The attachment does not know the method. paw gives it to the next attachment, then to the plugin. |
| `PAW_CALL_DONE` | Done. The answer is what the attachment wrote. |
| `PAW_CALL_FAILED` | Failed. What the attachment wrote tells why. |
| `PAW_CALL_STOPPED` | Call again with the plugin stopped. paw holds the audio thread off the plugin, deactivates it, calls again and activates it. The track is silent, or passes its sound through, for those blocks. |

### The calls of paw

| Method | Data | Answer |
| --- | --- | --- |
| `paw.file.load` | The file that paw kept for the attachment. Empty the first time. | Nothing. |
| `paw.clips` | The audio clips of the track, as JSON (below). | Nothing. |
| `paw.file.save` | Nothing. | The file to keep, or nothing. |

- paw sends `paw.file.load` when it makes the device, after the state of
  the plugin. A device that does not know it keeps no files and gets no
  clips.
- paw sends `paw.clips` after `paw.file.load`, and again each time the
  clips of the track or the tempo change: an edit, an undo, a project
  that opens. A device that does not know it is not asked again.
- paw sends `paw.file.save` when it keeps the states of the plugins: when
  it saves the project, renders, or starts the engine again.
- A render makes its own devices, which get the same calls.

### The clips

```json
{
  "track": { "id": 2, "name": "Vox" },
  "clips": [
    { "id": 5, "name": "take1", "file": "/song/media/take1.wav", "offset": 0.0,
      "start": 2.0, "length": 8.0, "stretch": 1.0, "gain": 0.0, "muted": false }
  ],
  "tempo": [ { "seconds": 0.0, "beat": 0.0 }, { "seconds": 5.0, "beat": 10.0 } ],
  "signatures": [ { "beat": 0.0, "num": 4, "den": 4 } ]
}
```

- `start` and `length` are seconds of the song. `offset` is seconds into
  the file. `gain` is dB.
- Only the audio clips of the track are in the list.
- `tempo` has a point at each tempo change, a point on each beat of a
  ramp, and a point after the last clip. Between two points the tempo is
  constant.

## What paw gives an attachment

`paw_attach_host` has these functions. They read sound files as paw
decodes them (WAV, AIFF, FLAC, MP3, Ogg Vorbis), always as two channels.

| Function | Effect |
| --- | --- |
| `audio_open(path, info)` | Open a file. `info` gets its frames, rate and channels. NULL when paw cannot read it. |
| `audio_read(audio, start, frames, channels, count)` | Read frames into one buffer for each channel. Frames outside the file are silence. Any thread. |
| `audio_close(audio)` | Close the file. |

## The file of an attachment

- The project keeps the file of an attachment as
  `<n>-<kind>.<name>` in the track folder, beside the `.state` of the
  device. `<name>` is the name of the attachment. `devices.json` names it
  under `file_names`. See [Project files](project-files.md).
- A project in one JSON file keeps it in `files`, base64 encoded.
