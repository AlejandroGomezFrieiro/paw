# How to punch in over a part

You can record again over some bars and keep the rest of the take. The
steps assume that the part has an input and is armed, and the rules are
in [Recording](../reference/recording.md#punch-in-and-out).

1. Select the bars to record again in visual mode, and press `gI`. The
   range shows red on the ruler.
2. If you want to hear the song before the punch in, type `:preroll 2`.
3. Stop the song and press `R`. The song plays from two bars before the
   punch in, and you play along. paw records only between the punch in
   and the punch out.
4. Stop the song. The new recording covers the range exactly. Over an
   audio clip, it becomes the take that plays in the range, and the old
   recording stays there as a take. Press `[t` to hear the old take again.

To give the range by bar numbers, type `:punch 5 8`.

If you want to record many takes of the range, also set the loop. Each
pass through the range then becomes a take (see
[How to record takes over a loop and comp them](record-takes-and-comp.md)).

To stop the punch, press `gI` again. paw keeps the range in the project
for the next time.
