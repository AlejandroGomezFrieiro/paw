# How to move a song between paw and REAPER

You can move a song between REAPER and paw, in both directions, with the
`interop` extension, which reads and writes REAPER projects (`.rpp`
files). The [interop README](../../extensions/interop/README.md) lists
what comes across. For Bitwig Studio, Studio One and Cubase, see
[How to move a song between paw and other DAWs](move-a-song-to-another-daw.md).

## Load the extension

Type `:ext.load interop`. If you want it to load at each start, see
[How to load an extension](load-an-extension.md).

## Open a REAPER project

1. Type `:e song.rpp`, with the path of the REAPER project. The tracks
   and the clips appear in the arrange view.
2. If a page opens, read it. It lists what paw could not bring across, for
   example plugins that paw does not have. Press `q` to close it.
3. To keep the project, save it as a project of paw: `:w song`.

If the MIDI tracks are silent because their instrument stayed in REAPER,
type `:e song.rpp instrument=synth`, and paw gives each of the silent
tracks a `synth`.

To add the tracks of a REAPER project to the open project, type
`:import song.rpp`.

## Save a project for REAPER

1. Type `:w song.rpp`, and paw writes the project as a REAPER project.
2. A page lists what paw could not write, for example the built-in
   devices of paw. Press `q` to close it.
3. Open `song.rpp` in REAPER. The tracks, folders, colors, clips, notes,
   controllers, automation and markers are there.

`:w song.rpp` does not change the project file of paw, and the project
stays the folder `song`.

## Work in both programs

You can move the same song from paw to REAPER and back many times, and
each time, paw reads what REAPER saved. Plugins that paw cannot use stay in
the song as placeholders. When you save for REAPER again, they return to
their places with their settings.
