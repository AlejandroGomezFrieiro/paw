# How to record takes over a loop and comp them

You can record many takes of one part, and then make one part from the
best pieces. The steps assume that the track has an input (see
[How to record a guitar or a bass](record-a-guitar-or-a-bass.md)). Each
key and command is in [Takes](../reference/takes.md).

## Record the takes

1. Select the bars of the part in visual mode, and press `gl` to loop
   them. Then arm the track with `r`.
2. Put the cursor at the loop start, or before it, and press `R`.
3. Play the part again each time round the loop.
4. Press `<Space><Space>` to stop. The clip shows the number of takes, for
   example `take 3 ‹3/3›`, and the last take plays.

A time round counts if it got to at least half of the loop.

You can also record audio again over a clip, with or without the loop.
Put the cursor where the clip starts and press `R`. The new recording
becomes the take that plays, and the clip keeps the old recording as
another take.

## Comp in the terminal

1. Press `zt` to show the take lanes below the track.
2. To hear the takes, press `]t` and `[t` on the clip.
3. For each range where a different take is better, do the following:
   1. Select the time range in visual mode.
   2. Type `:take 2`. paw cuts the clip at the ends of the selection, and
      take 2 plays there.

## Comp in the graphical window

1. Open the menu of the track and show the take lanes.
2. On the lane of the best take, press and drag across the time range.
   When you let go, that take plays over the range. To leave the grid,
   hold Shift while you drag.
3. To select a take for a full piece, click its lane over the piece.

## Finish

1. Listen to the comp. To change a choice, swipe or select again, because
   each piece keeps all its takes.
2. To delete the takes that do not play, type `:take.keep`.
3. If you want to keep the other takes on new tracks instead, type
   `:take.explode`.
