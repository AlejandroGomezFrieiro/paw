# How to record takes over a loop and comp them

This guide shows you how to record many takes of one part, and make one
part from the best pieces. It assumes that the track has an input (see
[How to record a guitar or a bass](record-a-guitar-or-a-bass.md)). For each key and
command, see [Takes](../reference/takes.md).

## Record the takes

1. Select the bars of the part in visual mode, and press `gl` to loop
   them.
2. Arm the track with `r`.
3. Put the cursor at the loop start, or before it. Press `R`.
4. Play the part again on each time round the loop.
5. Press `<Space><Space>` to stop. The clip shows the number of takes, for
   example `take 3 ‹3/3›`. The last take plays.

A time round counts if it reached at least half of the loop.

## Comp in the terminal

1. Press `zt` to show the take lanes below the track.
2. To hear the takes, press `]t` and `[t` on the clip.
3. Select the time range where a different take is better, in visual mode.
4. Type `:take 2`. paw cuts the clip at the ends of the selection, and
   take 2 plays there.
5. Do steps 3 and 4 again for each range.

## Comp in the graphical window

1. Open the menu of the track and show the take lanes.
2. On the lane of the best take, press and drag across the time range.
   On release, that take plays over the range.
3. To select a take for a full piece, click its lane over the piece.
4. To leave the grid, hold Shift while you drag.

## Finish

1. Listen to the comp. To change a choice, swipe or select again. Each
   piece keeps all its takes.
2. To delete the takes that do not play, type `:take.keep`.
3. To keep the other takes on new tracks instead, type `:take.explode`.
