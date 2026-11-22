# How to import audio and MIDI files

You can bring sound files and MIDI files into a project. paw reads WAV,
AIFF, FLAC, MP3 and Ogg files, and standard MIDI files. The rules are in
[Recording](../reference/recording.md#import-sound-files),
[MIDI](../reference/midi.md#midi-files) and
[The file manager](../reference/file-manager.md).

## Import with a command

- To put a sound file on a new track, type `:import /home/ana/samples/loop.wav`.
  The track gets the name of the file, and the clip starts at the cursor.
- To put a sound file on the track of the cursor, at the cursor, type
  `:clip.import /home/ana/samples/loop.wav`.
- To add the tracks of a MIDI file, type `:import /home/ana/riff.mid`. The
  tracks go below the track of the cursor, and they start at the cursor.
  If you also want the tempo map of the file, add `tempo=yes`.

Type `:import` with no name to choose the file from a list. `Tab`
completes the names of files.

To open a MIDI file as a new project, type `:e /home/ana/riff.mid`.

## Import from the file manager

1. Type `:files /home/ana/samples`, and the folder opens as a list of
   files, with the length of each sound file.
2. Move to a file with `j` and `k`, or find it with `/loop`. To hear the
   file first, press `gh`.
3. Press `Enter` to put the file on the track of the arrange cursor, at
   the cursor, or press `go` to put it on a new track.

## Import in the graphical window

- On X11, drag sound files or MIDI files from your file manager into the
  window. Each sound file goes on a new track, at the edit cursor.
- Or choose File → Import….

An imported file stays in its own folder. To copy the files into the
`media` folder of the project, type `:media.collect`, as
[How to save, back up and open projects](save-and-open-projects.md) shows.
