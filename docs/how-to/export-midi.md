# How to export MIDI for another program

This guide shows you how to write the notes of paw to a MIDI file. Another
program, for example a notation program or a different DAW, can then open
the file. For each rule, see [MIDI](../reference/midi.md#midi-files).

## Export the whole song

Type `:export /home/ana/Music/song.mid`. paw writes each MIDI track as a
track of the file. The file also gets the tempo map, the time signatures
and the markers. The message says how many notes it wrote.

## Export one clip

1. Put the cursor on the clip in the arrange view.
2. Type `:export /home/ana/Music/riff.mid clip`.

## Export some tracks

1. Select the tracks in visual mode, for example `Vj` for this track and
   the next track.
2. Type `:export /home/ana/Music/part.mid selection`.

paw writes a standard MIDI file of format 1. Audio clips and muted clips
are not in the file. To send the sound, render it (see
[How to export a song as WAV, FLAC or MP3](export-a-song.md)).

To bring a MIDI file into paw, see
[How to import audio and MIDI files](import-audio-and-midi-files.md).
