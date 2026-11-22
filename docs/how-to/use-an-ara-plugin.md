# How to use an ARA plugin on a vocal or a take

You can put an ARA plugin on a track, and then make a MIDI clip of the
notes that the plugin heard. An ARA plugin reads the full audio clips of a
track. It can edit the notes of a vocal, or write the notes of a take as
MIDI. [About ARA plugins](../explanation/about-ara.md) explains what ARA
is.

You need the [ara extension](../../extensions/ara/README.md) and a CLAP
plugin with ARA. Windows plugins that run through yabridge do not give
ARA.

## Put the plugin on the track

1. Load the extension: `:ext.load ara`. `:checkhealth ara` lists the ARA
   plugins that paw knows, and if the list is empty, type
   `:plugins.rescan`.
2. Put the cursor on the audio track.
3. Press `\aa` and choose the plugin. The message says the plugin and the
   number of clips that it has.

The plugin is first on the track, and it plays the clips of the track from
their files.

## Edit in the plugin

1. Press `\ae` to open the window of the plugin.
2. Edit as the plugin lets you. paw saves the edits with the project, in
   a `.ara` file beside the state of the plugin.

Move or delete a clip as usual, and the plugin gets the change at once.

## Make a MIDI clip of the notes

1. Press `\an`, and paw waits while the plugin listens to the clips.
2. A new track `<track> notes` under the track holds a MIDI clip of the
   notes. Press `u` to remove it.

`extensions/ara/tests.lua` does the same steps with the test plug-in of
the ARA SDK.
