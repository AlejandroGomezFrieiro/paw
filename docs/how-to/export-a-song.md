# How to export a song as WAV, FLAC or MP3

You can export the song to a sound file, such as a WAV master or an MP3 to
share. Each word of the command is in [Export](../reference/export.md).

## Export the song

1. Save the project with `:w`.
2. Type `:export`. paw renders the song to a WAV file with the name of the
   project, in the folder `renders` of the project: `song/renders/song.wav`.
3. Wait for the message that gives the length and the peak of the file.
   The status line shows the progress, and you can press `Esc` to stop the
   export.

The file starts at the start of the song. It ends two seconds after the
last clip, so that the tail of reverbs and delays is in the file.

## Choose the format and the place

Give the file name after `:export`, and its extension sets the format:

- `:export /home/ana/Music/song.wav` for a WAV file, at 24 bits.
- `:export /home/ana/Music/song.flac` for a FLAC file.
- `:export /home/ana/Music/song.mp3 quality=best` for an MP3 file at 320 kbit/s.

If you give a name without a folder, for example `:export mix.flac`, the
file goes into the folder `renders` of the project, which keeps the
exported files apart from the files of the project. Before the first save,
it goes into the folder where you started paw.

`:export review` writes an MP3 file to listen to, at the loudness of the
streaming services.

If `:export song.mp3` fails because there is no `ffmpeg`, install
`ffmpeg`. WAV and FLAC need no other program.

## Add the tags

1. Type the tags of the project one time:

   ```
   :export.tags artist=Ana album="First one" track=3/12 year=2026 cover=cover.png
   ```

2. Export as above. paw writes the tags into each file, and FLAC, MP3, Ogg
   and Opus files get the cover too.

## Common options

- For a CD, add `rate=44100 bits=16 dither=true`.
- If the reverb continues after the end, add `tail=4` for four seconds.
- For a loudness target, add `loudness=-14`. To also keep the peaks below
  a level, add `normalize=-1`.

To export the same way each time, save the words as a preset: see
[How to reuse your export settings](reuse-export-settings.md).
To export one part of the song, see
[How to export part of the song or a loop](export-part-of-the-song.md).
To export each part, see [How to export stems](export-stems.md).

In the graphical window, choose File → Render…, choose the format and the
options, type the tags under Tags, and start the render.
