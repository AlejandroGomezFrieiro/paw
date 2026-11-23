# How to export part of the song or a loop

You can export only a part of the song, such as the loop, a selection, or
a named section. Each word is in [Export](../reference/export.md).

## Export the loop

1. Put the cursor at the start of the part, and type `gl4W` to loop four
   bars from the cursor.
2. Type `:export /home/ana/Music/loop.wav in=loop tail=0`.

`tail=0` stops the file at the loop end, so the file loops cleanly in a
sampler. Without it, the file has two more seconds for the tail of the
reverbs.

## Export a selection

1. Select the bars in visual mode, for example `v2W`.
2. Type `:`, and paw types the range of the selection, `'<,'>`. Then type
   `export /home/ana/Music/part.wav`.

The file holds the tracks and the bars of the selection.

## Export some bars

Type the bars before the command: `:17,32export /home/ana/Music/bridge.wav`
exports bars 17 to 32.

## Export a section by name

1. Select the bars of the section in visual mode.
2. Type `:region Verse`, and paw makes a region with that name over the
   selection.
3. Type `:export /home/ana/Music/verse.wav in=Verse`.

To export each region to a file of its own, type
`:export regions /home/ana/Music/parts/`. paw shows the plan of the files,
and `y` writes `01 Intro.wav`, `02 Verse.wav` and the next files into the
folder.

If your regions are inside other regions, choose a level:

- To export only the large sections, add `level=1`.
- To export only the smallest parts, add `level=leaves`.

A file of a region inside a region has the path in its name, for example
`02 Chorus 2 - Verse A.wav`.

To export each track of the part, see
[How to export stems](export-stems.md).
