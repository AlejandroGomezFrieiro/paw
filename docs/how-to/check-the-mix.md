# How to check the mix

This guide shows you how to measure the mix before you render it. You
measure the levels, the loudness, and the sound in mono. It uses the meters
of the mixer and the `mixdiag` extension. For each measurement, see the
[mixdiag README](../../extensions/mixdiag/README.md).

## Watch the meters

1. Press `<Space>m` to show the mixer.
2. Press `<Space><Space>` to play the loudest part of the song.
3. Look at the meters of each strip and of the Master strip. The number
   under the meters is the highest recent level. The top row turns red
   when a level reaches full scale.

If the master goes red, see
[How to set levels and pan](set-levels-and-pan.md).

## Measure the song

1. Type `:ext.load mixdiag`. To load it at each start, see
   [How to load an extension](load-an-extension.md).
2. To choose the target, press `<Space>xt` until the message names it. Use
   `streaming` for a song that goes to Spotify or a similar service. Use
   `ebu` for radio and television.
3. Press `<Space>xa`. The status line shows `measuring` and a percentage.
4. At the end, a message gives the integrated loudness (LUFS), the true
   peak (dBTP) and the loudness range (LRA).
5. Press `<Space>xr` to open the report. Press `j` and `k` to choose a finding,
   and `Enter` to go to its place in the song. Press `q` to close the
   report.
6. Correct the mix, and press `<Space>xa` again.

To measure only the loop, press `<Space>xl`. To measure what one track adds,
put the cursor on it and press `<Space>xk`.

## Check the mix in mono

1. Press `<Space>xa` to measure the song.
2. Press `<Space>xs`. The message gives the mono loss: how much quieter the mix
   is in mono.
3. If the mix cancels in mono, the report has a `mono` finding. A `phase`
   finding gives the place where the sides cancel. To go to that place,
   press `]d` in the arrange view.

A stereo effect with one side upside down, or two microphones at
different distances, can cancel in mono. To correct one track, put a
`utility` device on it, and set `invert_l` or `invert_r`.

In the graphical window, choose More ▸ Mix report.
