# How to export a song as WAV, FLAC or MP3

You can render the song to a sound file, such as a WAV master or an MP3 to
share. In paw, the command to export is `:render`, and each option is in
[Render](../reference/render.md).

## Export the song

1. Save the project with `:w`.
2. Type `:render`. paw renders the song to a WAV file with the name of the
   project, in the folder `renders` of the project: `song/renders/song.wav`.
3. Wait for the message that gives the length and the peak of the file.
   The status line shows the progress, and you can press `Esc` to stop the
   render.

The render starts at the start of the song. It ends one second after the
last clip, so that the tail of reverbs and delays is in the file.

## Choose the format and the place

Give the file name after `:render`, and its extension sets the format:

- `:render /home/ana/Music/song.wav` for a WAV file, at 24 bits.
- `:render /home/ana/Music/song.flac` for a FLAC file.
- `:render /home/ana/Music/song.mp3 quality=best` for an MP3 file at 320 kbit/s.

If you give a name without a folder, for example `:render mix.flac`, the
file goes into the folder of the project. Before the first save, it goes
into the folder where you started paw.

`:render` with no name always writes into the folder `renders` of the
project, which keeps the rendered files apart from the files of the
project.

If `:render song.mp3` fails because there is no `ffmpeg`, install
`ffmpeg`. WAV and FLAC need no other program.

## Add the tags

1. Type the tags of the project one time:

   ```
   :render.tags artist=Ana album="First one" track=3/12 year=2026 cover=cover.png
   ```

2. Render as above. paw writes the tags into each file, and FLAC, MP3, Ogg
   and Opus files get the cover too.

## Common options

- For a CD, add `rate=44100 bits=16 dither=true`.
- If the reverb continues after the end, add `tail=4` for four seconds.
- For a loudness target, add `loudness=-14`. To also keep the peaks below
  a level, add `normalize=-1`.

To export one part of the song, see
[How to export part of the song or a loop](export-part-of-the-song.md).
To export each track, see [How to render stems](render-stems.md).

In the graphical window, choose File → Render…, choose the format and the
options, type the tags under Tags, and start the render.
