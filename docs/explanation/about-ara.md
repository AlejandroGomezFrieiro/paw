# About ARA plugins

An ARA plugin can read a whole clip at any time, before or after the
playback position, while a usual plugin sees the sound one block at a time
while the song plays. For example, Melodyne finds the notes of a vocal in
that way and then changes them. Synthesizer V reads the notes of its vocal
tracks, and an audio-to-MIDI plugin hears all of a take before it writes
the notes.

ARA (Audio Random Access, version 2) is the interface between the host and
such a plugin, and Celemony publishes it under the Apache 2.0 license in
the ARA SDK. The page explains how ARA works, how paw hosts it, and why
the parts are where they are. For the keys and commands, see the
[ara extension](../../extensions/ara/README.md). For the interface that the
extension uses, see [Attachments](../reference/attachments.md).

## The model of ARA

The host describes its song to the plugin as a document, which has these
parts:

- A musical context is the timeline, which means the tempo map and the time
  signatures. The plugin reads them from the host through content readers.
- An audio source is a sound file. The plugin reads its samples through an
  audio reader that the host gives, from any thread and at any time, and it
  analyzes them.
- An audio modification holds the edits of the plugin to one source, so
  two clips of the same file can have different edits.
- A region sequence is a track, and a playback region puts a part of an
  audio modification on the timeline, in seconds.

One plugin instance is bound to the document. Its roles are playback
renderer, which plays the regions, and editor renderer and editor view,
which means that its window shows the regions. The host gives the regions
to the renderer only while the plugin is not active.

The host also asks the plugin what it found, e.g., notes, tempo, key and
chords, through content readers. It stores the state of the document as an
ARA archive in its project, and it gives the archive back when the project
opens.

ARA attaches to a plugin format. A CLAP plugin gives the
`org.ara-audio.ara.pluginextension/2` extension, which has the ARA factory
and the call that binds the plugin to a document controller. A VST3 plugin
gives `ARA::IMainFactory` from its factory and `ARA::IPlugInEntryPoint2`
from its component, for the same purposes.

## Where paw hosts ARA

The host side of ARA must run in the helper process of the plugin. ARA is a
C interface with pointers between the host and the plugin, so the document
controller and the plugin must be in the same process, and paw runs each
plugin in a helper process of its own (see
[About the plugin sandbox](about-the-plugin-sandbox.md)).

The ARA host is not in the core, because a feature that only some users
need is an extension (see
[About the core and extensions](about-core-and-extensions.md)). The ARA
code is in `extensions/ara`, and the core has three generic parts that it
uses:

- Attachments. The core loads a native library from an extension into each
  process that hosts plugins, and it offers the library each CLAP plugin
  before the plugin is active. The library can use the extensions of the
  plugin, and it answers calls to the device. When it must change what the
  plugin plays, it asks the core to stop the plugin for the call.
- Clips for a device. The core gives a device the audio clips of its track
  and the tempo as JSON, and gives them again after each change. Undo, a
  moved clip and a new tempo get to the plugin in the same way.
- Files beside the state. A device can keep a file of its own in the
  project, beside the `.state` of the plugin, and the ARA archive is such a
  file.

The extension's native part, `paw-ara.so`, makes the ARA document from the
clips. It gives the plugin the audio reader and the content readers, and it
writes and reads the archive. The extension's Lua code puts ARA plugins on
tracks and makes MIDI clips from the notes that a plugin found.

## MIDI and the project stay the truth

The clips of the track decide what the plugin gets, and the plugin owns
only its edits, in its archive. A project opens and plays without the
extension, and the clips then play as they are, without the edits of the
plugin. The design follows
[About MIDI as the truth](about-midi-as-the-truth.md).

## Plugins that run through yabridge

Synthesizer V Studio 2 and MIDI Guitar 3 are Windows plugins, and on Linux
they run through yabridge. yabridge carries VST2, VST3 and CLAP calls
between the Linux host and the Windows plugin in Wine, but it does not
carry the ARA interface. The two plugins therefore work in paw as usual
plugins without ARA. To use their ARA side in paw, one of the following
must happen:

- yabridge carries the ARA interface across the two processes, which means
  its document controller, the host interfaces and the audio reader. The
  ARA SDK has an IPC layer (`ARA_Library/IPC`) for that purpose, which the
  SDK uses on macOS and Windows.
- The vendor builds the plugin for Linux with ARA, as CLAP or VST3, and paw
  then hosts it like it hosts the test plug-in. For VST3, the extension
  needs the VST3 binding, which it does not have now.

## Sources

- The ARA SDK: <https://github.com/Celemony/ARA_SDK>, release 2.3.0, with
  the interface, the library and the examples. `ARA_API/ARAInterface.h`
  describes the interface, `ARA_API/ARACLAP.h` the CLAP binding and
  `ARA_API/ARAVST3.h` the VST3 binding.
- The test plug-in that the tests host: `ARA_Examples/TestPlugIn`.
- yabridge: <https://github.com/robbert-vdh/yabridge>.
