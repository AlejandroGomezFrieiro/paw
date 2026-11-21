# How to set levels and pan, and keep the master out of the red

This guide shows you how to balance the tracks with the faders and the
pan. It also shows how to keep the master below full scale. For each key, see
[The mixer](../reference/mixer-view.md).

## Set the level and the pan of a track

1. Press `<Space>mm` to show the mixer. Each track has a strip.
2. Press `h` and `l` to go from strip to strip. Press `0` for the first
   strip.
3. Press `-` to lower the fader by one dB, and `+` to raise it. A count
   gives the dB: `6-` lowers the fader by 6 dB.
4. To type a level, press `grv`. Type `-6` and press `Enter`. The fader
   goes to -6 dB.
5. Press `]` to pan to the right, and `[` to pan to the left. Each press
   moves the pan by a tenth.
6. To type a pan, press `grp`. Type `L30`, `R25` or `C`, and press `Enter`.

In the `grv` prompt, a number is the level: `-6` is -6 dB and `+2` is
+2 dB. To change the level by a step, put `=` after the sign. `-=3` lowers
the fader by 3 dB. `+=2` raises it by 2 dB. Each prompt that asks for a
value has the same rule.

The same keys work on a track in the arrange view: `+`, `-`, `]`, `[`,
`grv` and `grp`.

In the graphical window, drag the fader or the pan of a strip. A double
click resets it.

## Keep the master out of the red

1. Play the loudest part of the song with `<Space><Space>`.
2. Look at the meters of the Master strip, at the right of the mixer. The
   number under the meters is the highest recent level.
3. If the top row of the meters turns red, the mix reached full scale. It
   clips.
4. Lower all the tracks together. Press `0`, then `V$` to select all the
   strips. Press `6-` to lower each fader by 6 dB. Press `Esc`.
5. Play the part again. To reset the red light, click it, or start the
   song again.

To catch the peaks that remain, add a limiter to the master:

1. Press `$` to go to the Master strip. In the arrange view, press `j` on
   the last track.
2. Press `a`, type `Limiter` and press `Enter`. The limiter keeps the
   peaks below -1 dB.

The keys `+`, `-`, `grv` and `a` also work on the master.

For the loudness of the mix, see [How to check the mix](check-the-mix.md).
