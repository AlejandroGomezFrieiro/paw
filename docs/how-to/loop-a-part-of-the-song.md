# How to loop a part of the song while you work

<!-- tags: loop-a-part -->

This guide shows you how to play a part of the song again and again, for
example a chorus. Then you can change it while it plays. The loop shows as a band on
the ruler, and the status line gives its bars, for example `loop 2–3`.

## Loop a clip or bars

- To loop the clip under the cursor, press `glic`.
- To loop the bar of the cursor, press `glib`. To loop two bars from the
  bar of the cursor, press `gl2ib`.
- To loop a range of time, press `v`, move the cursor to the end of the
  range, and press `gl`.

`gl` also turns the loop on. Press `<Space><Space>` to play. At the end of the
loop, the playhead returns to its start.

## Loop a region

If the song has a region, for example `Chorus`, type
`:region.loop Chorus`, or put the cursor in it and press `<Space>rl`. To make
a region over the loop, type `:region Chorus`. To make a region over a
selection, select the bars with `v`, press `<Space>rn` and type its name.

## Turn the loop off and on

Press `gL`. The loop keeps its start and end, so `gL` again plays the same
part.

In the graphical window, drag in the top half of the ruler to loop that
range. Double-click the ruler to turn the loop off or on.

## See also

- [How to record takes over a loop and comp them](record-takes-and-comp.md)
- [Markers and regions](../reference/markers.md)
