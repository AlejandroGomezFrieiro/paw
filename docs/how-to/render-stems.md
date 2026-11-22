# How to render stems

You can render the parts of a song to separate files, called stems. Each
option is in [Render](../reference/render.md#stems).

## One file for each group

1. Put the tracks of each part into a group (`<Space>tg` on the selected tracks).
2. Type `:render stems`. paw shows the plan, with each file and the tracks
   that it holds.
3. Press `y` or `Enter` to render. The files go into the folder
   `renders/stems` of the project, for example `song/renders/stems`.

Each file has all the sound that its group goes through, so the files add
up to the mix.

To use a different folder, type `:render stems out`. To render FLAC, add
`format=flac`. To render without the devices of the master, add
`master=false`.

## One file for each track

1. Type `:render stems tracks`.
2. Press `y` or `Enter`.

## One group

Type `:render Strings`, and paw writes `renders/Strings.wav` in the folder
of the project.

A compressor or a limiter on a shared bus hears each stem alone, so the
stems then do not add up exactly to the mix.
