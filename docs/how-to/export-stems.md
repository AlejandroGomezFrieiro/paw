# How to export stems

You can export the parts of a song to separate files, called stems. Each
word is in [Export](../reference/export.md#stems).

## One file for each group

1. Put the tracks of each part into a group (`<Space>tg` on the selected tracks).
2. Type `:export stems`, or press `<Space>es`. paw shows the plan, with
   each file and the tracks that it holds.
3. Press `y` or `Enter` to export. The files go into the folder
   `renders/stems` of the project, for example `song/renders/stems`.

Each file has all the sound that its group goes through, so the files add
up to the mix.

To use a different folder, type `:export stems out/`. To export FLAC, add
`format=flac`. To export without the devices of the master, add
`tap=groups`.

## Bring the stems to one level

To export the stems at a peak level or a loudness, add `normalize=` or
`loudness=`, for example `:export stems normalize=-1`. paw first renders
the mix and measures it. Then it gives each stem the gain that brings the
mix to that level, so the stems still add up to the mix. The plan says so
in a note.

## One file for each track

1. Type `:export tracks`, or press `<Space>et`.
2. Press `y` or `Enter`.

Each file has the track with its devices, fader and pan, but not its
groups or the master.

## One group

Type `:t/Strings/export`, and paw writes `renders/Strings.wav` in the
folder of the project.

A compressor or a limiter on a shared bus hears each stem alone, so the
stems then do not add up exactly to the mix. The plan says when this
happens.
