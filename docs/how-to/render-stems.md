# How to render stems

This guide shows you how to render the parts of a song to separate
files. For each option, see
[Render](../reference/render.md#stems).

## One file for each group

1. Put the tracks of each part into a group (`<Space>g` on the selected tracks).
2. Type `:render stems`. paw shows the plan: each file, and the tracks that
   it holds.
3. Press `y` or `Enter` to render. The files go into `<project> stems`.

Each file has all the sound that its group goes through, so the files add
up to the mix.

To use a different folder, type `:render stems out`. To render FLAC, add
`format=flac`. To render without the devices of the master, add
`master=false`.

## One file for each track

1. Type `:render stems tracks`.
2. Press `y` or `Enter`.

## One group

1. Type `:render Strings`. paw writes `Strings.wav` next to the project.

A compressor or a limiter on a shared bus hears each stem alone. Then the
stems do not add up exactly to the mix.
