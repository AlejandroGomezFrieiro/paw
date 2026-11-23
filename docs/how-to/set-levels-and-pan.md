# How to set levels and pan, and keep the master out of the red

You can balance the parts with the faders and the pan, and keep the
master below full scale. Each key is in
[The mixer](../reference/mixer-view.md).

<!-- paw-live: {"project": "demo-song"} -->

## Set the level and the pan of a part

1. Press `<Space>mm` to show the mixer, where each part has a strip.
   Press `h` and `l` to go from strip to strip, and `0` for the first
   strip.
2. Set the level:
   - Press `-` to lower the fader by one dB, and `+` to raise it. A count
     gives the dB, so `6-` lowers the fader by 6 dB.
   - To type a level, press `grv`, type `-6` and press `Enter`. The fader
     goes to -6 dB.
3. Set the pan:
   - Press `]` to pan to the right, and `[` to pan to the left. Each press
     moves the pan by a tenth.
   - To type a pan, press `grp`, type `L30`, `R25` or `C`, and press
     `Enter`.

In the `grv` prompt, a number is the level, so `-6` is -6 dB and `+2` is
+2 dB. To change the level by a step, put `=` after the sign. For example,
`-=3` lowers the fader by 3 dB, and `+=2` raises it by 2 dB. Each prompt
that asks for a value has the same rule.

The same keys work on a part in the arrange view: `+`, `-`, `]`, `[`,
`grv` and `grp`.

In the graphical window, drag the fader or the pan of a strip, and a
double click resets it.

## Keep the master out of the red

1. Play the loudest part of the song with `<Space><Space>`.
2. Look at the meters of the Master strip, at the right of the mixer. The
   number under the meters is the highest recent level. If the top row of
   the meters turns red, the mix got to full scale, and it clips.
3. Lower all the parts together. Press `0`, and then `V$` to select all
   the strips. Press `6-` to lower each fader by 6 dB, and press `Esc`.
4. Play the part again. To reset the red light, click it, or start the
   song again.

To catch the peaks that remain, add a limiter to the master:

1. Press `$` to go to the Master strip. In the arrange view, press `j` on
   the last part.
2. Press `a`, type `Limiter` and press `Enter`. The limiter keeps the
   peaks below -1 dB.

The keys `+`, `-`, `grv` and `a` also work on the master.

For the loudness of the mix, see [How to check the mix](check-the-mix.md).
