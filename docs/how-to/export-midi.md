# How to export MIDI for another program

You can write the notes of paw to a MIDI file for another program, such
as a notation program or a different DAW. The rules are in
[Export](../reference/export.md#midi-files) and
[MIDI](../reference/midi.md#midi-files).

## Export the whole song

Type `:export /home/ana/Music/song.mid`, and paw writes each MIDI track as
a track of the file. The file also gets the tempo map, the time signatures
and the markers, and the message says how many notes paw wrote.

## Export one clip

1. Put the cursor on the clip in the arrange view.
2. Type `:export clip /home/ana/Music/riff.mid`.

## Export some tracks

1. Select the tracks in visual mode, for example `Vj` for the current
   track and the next track.
2. Type `:`, and paw types the range of the selection, `'<,'>`. Then type
   `export /home/ana/Music/part.mid`.

## Export each track to a file of its own

Type `:export /home/ana/Music/{track}.mid each=track`, and paw writes
`Bass.mid`, `Lead.mid` and a file for each other track.

paw writes a standard MIDI file of format 1, without the audio clips and
the muted clips. If you want to send the sound, export it as
[How to export a song as WAV, FLAC or MP3](export-a-song.md) shows.

To bring a MIDI file into paw, see
[How to import audio and MIDI files](import-audio-and-midi-files.md).
