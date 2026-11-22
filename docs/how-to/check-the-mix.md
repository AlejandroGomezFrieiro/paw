# How to check the mix

You can measure the levels, the loudness and the mono sound of the mix
before you render it. The steps use the meters of the mixer and the
`mixdiag` extension, and each measurement is described in the
[mixdiag README](../../extensions/mixdiag/README.md).

## Watch the meters

1. Press `<Space>mm` to show the mixer.
2. Press `<Space><Space>` to play the loudest part of the song.
3. Look at the meters of each strip and of the Master strip. The number
   under the meters is the highest recent level, and the top row turns red
   when a level gets to full scale.

If the master goes red, see
[How to set levels and pan](set-levels-and-pan.md).

## Measure the song

1. Type `:ext.load mixdiag`. If you want it to load at each start, see
   [How to load an extension](load-an-extension.md).
2. To choose the target, press `<Space>mt` until the message names it. Use
   `streaming` for a song that goes to Spotify or a similar service, and
   `ebu` for radio and television.
3. Press `<Space>ma`, and the status line shows `measuring` and a
   percentage. At the end, a message gives the integrated loudness (LUFS),
   the true peak (dBTP) and the loudness range (LRA).
4. Press `<Space>mr` to open the report:
   1. Press `j` and `k` to choose a finding, and `Enter` to go to its
      place in the song.
   2. Press `q` to close the report.
   3. Correct the mix, and press `<Space>ma` again.

To measure only the loop, press `<Space>ml`. To measure what one track adds,
put the cursor on it and press `<Space>mk`.

## Check the mix in mono

1. Press `<Space>ma` to measure the song.
2. Press `<Space>ms`. The message gives the mono loss, which is how much
   quieter the mix is in mono.
3. If the mix cancels in mono, the report has a `mono` finding, and a
   `phase` finding gives the place where the sides cancel. To go to that
   place, press `]d` in the arrange view.

A stereo effect with one side upside down, or two microphones at
different distances, can cancel in mono. To correct one track, put a
`utility` device on it, and set `invert_l` or `invert_r`.

In the graphical window, choose More ▸ Mix report.
