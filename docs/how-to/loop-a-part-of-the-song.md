# How to loop a part of the song while you work

<!-- tags: loop-a-part -->

Here is how to play a part of the song again and again, for
example a chorus, and change it while it plays. The playback loop is the
stretch of the song that repeats while it plays or records. It is not
`:clip.repeat`, which repeats the content of one clip when you make the clip
longer.

## Loop a selection

1. Press `v` and move the cursor over the time to loop. In the arrange view,
   `V` selects whole tracks, and the loop takes their time.
2. Press `gl`. The message says what the loop is, for example
   `loop: bars 5 to 8, on`.
3. Press `<Space><Space>` to play. At the end of the loop, the playhead
   returns to its start.

`gl` also works with a motion, so you do not need to select first.

- To loop the clip under the cursor, press `glic`.
- To loop the region that the cursor is in, press `glar`.
- To loop the bar of the cursor, press `glib`. To loop two bars from the
  bar of the cursor, press `gl2ib`.

You can also type the range. `:5,9loop` loops bars 5 to 9, and
`:'<,'>loop` loops the last selection.

## Loop a region by name

If the song has a region, for example `Chorus`, type
`:region.loop Chorus`, or put the cursor in it and press `<Space>rl`.

You can also make a region from the loop or from a selection. To make a
region over the loop, type `:region Chorus`. To make a region over a
selection, select the bars with `v`, press `<Space>rn` and type its name.

## See whether looping is on

While looping is on, the ruler shows the loop as a bright band, the lanes
are shaded in the same range, and the status line shows `loop 5–8`. While
it is off, the band stays on the ruler in dim colors and the status line
shows `loop off 5–8`. The graphical window draws the same band, and its loop
button is lit while looping is on. All of this is the same while the song
plays and while it records.

## Turn the loop off and on

Press `gL`, or type `:loop off` and `:loop on`. The loop keeps its start and
end, so when you turn it on again, it plays the same part.

In the graphical window, drag in the top half of the ruler to loop that
range. Double-click the ruler to turn the loop off or on.

## See also

- [How to record takes over a loop and comp them](record-takes-and-comp.md)
- [Markers and regions](../reference/markers.md)
