# How to use an ARA plugin on a vocal or a take

An ARA plugin reads the full audio clips of a track. It can edit the
notes of a vocal, or write the notes of a take as MIDI. This guide puts
an ARA plugin on a track. Then it makes a MIDI clip of the notes that the
plugin heard. For what ARA is, see
[About ARA plugins](../explanation/about-ara.md).

You need the [ara extension](../../extensions/ara/README.md) and a CLAP
plugin with ARA. Windows plugins through yabridge do not give ARA.

## Put the plugin on the track

1. Load the extension: `:ext.load ara`. `:checkhealth ara` lists the ARA
   plugins that paw knows. If the list is empty, type `:plugins.rescan`.
2. Put the cursor on the audio track.
3. Press `\aa` and choose the plugin. The message says the plugin and the
   number of clips that it has.

The plugin is first on the track. It plays the clips of the track, from
their files.

## Edit in the plugin

1. Press `\ae` to open the window of the plugin.
2. Edit as the plugin lets you. paw saves the edits with the project, in
   a `.ara` file beside the state of the plugin.

Move or delete a clip as usual: the plugin gets the change at once.

## Make a MIDI clip of the notes

1. Press `\an`. paw waits while the plugin listens to the clips.
2. A new track `<track> notes` under the track holds a MIDI clip of the
   notes. Press `u` to remove it.

`extensions/ara/tests.lua` does these steps with the test plug-in of
the ARA SDK.
