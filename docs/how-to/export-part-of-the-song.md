# How to export part of the song or a loop

This guide shows you how to render only a part of the song. The part can
be the loop, a selection, or a named section. For each option, see
[Render](../reference/render.md).

## Export the loop

1. Put the cursor at the start of the part. Type `gl4W` to loop four bars
   from the cursor.
2. Type `:render /home/ana/Music/loop.wav range=loop tail=0`.

`tail=0` stops the file at the loop end. Then the file loops cleanly in a
sampler. Without it, the file has one more second for the tail of the
reverbs.

## Export a selection

1. Select the bars in visual mode, for example `v2W`.
2. Type `:render /home/ana/Music/part.wav range=selection`.

## Export a section by name

1. Select the bars of the section in visual mode.
2. Type `:region Verse`. paw makes a region with that name over the
   selection.
3. Type `:render /home/ana/Music/verse.wav range=Verse`.

To export each region to a file of its own, type
`:render.regions /home/ana/Music/parts`. paw writes `01 Intro.wav`,
`02 Verse.wav` and the next files into that folder.

If your regions are inside other regions, choose a level:

- To export only the large sections, add `level=1`.
- To export only the smallest parts, add `level=leaves`.

A file of a region inside a region has the path in its name, for example
`02 Chorus 2 - 01 Verse A.wav`.

To export a range of beats, add `start=16 end=32`.

To export each track of the part, see
[How to render stems](render-stems.md).
