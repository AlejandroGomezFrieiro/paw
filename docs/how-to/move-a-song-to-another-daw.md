# How to move a song between paw and other DAWs

This guide shows you how to move a song between paw and another DAW, in
both directions. Bitwig Studio, PreSonus Studio One and Steinberg Cubase
read and write DAWproject files (`.dawproject`). The `interop` extension
does this for paw. For a list of what comes across, see the
[interop README](../../extensions/interop/README.md). For REAPER,
see [How to move a song between paw and REAPER](open-a-reaper-project.md).

## Load the extension

Type `:ext.load interop`. To load it at each start, see
[How to load an extension](load-an-extension.md).

## Open a song from another DAW

1. In the other DAW, export the song as a DAWproject file. The manual of
   that DAW tells you how.
2. In paw, type `:e song.dawproject`, with the path of the file. The
   tracks and the clips appear in the arrange view. paw puts the audio
   files in a folder beside the file, `song media`.
3. If a page opens, read it. It lists what paw could not bring across,
   for example plugins that paw does not have. Press `q` to close it.
4. To keep the song, save it as a project of paw: `:w song`.

To add the tracks of the file to the open project, type
`:import song.dawproject`.

## Save a song for another DAW

1. Type `:w song.dawproject`. paw writes the song, the states of its
   plugins and its audio files into this one file.
2. A page lists what paw could not write, for example the built-in
   devices of paw. Press `q` to close it.
3. In the other DAW, open `song.dawproject`.

The file can be large, because it holds the audio. To refer to the audio
files where they are, type `:export song.dawproject embed=false`.
Then keep the file and the audio files on the same computer.

`:w song.dawproject` does not change the project file of paw. The project
stays the folder `song`.
