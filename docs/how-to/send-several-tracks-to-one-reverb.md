# How to send several tracks to one reverb

This guide shows you how to send several tracks to one reverb on a track
of its own. The tracks then share one room. For each rule, see
[Routing](../reference/routing.md#outputs-and-sends).

## Make the reverb track

1. Put the cursor on the last track, and press `o` to add a track below.
2. Press `grn`, type `Reverb` and press `Enter`.
3. Press `a`, type `Reverb` and press `Enter`. paw puts a reverb on the
   track.
4. Press `<Space>d` to show the device panel. Press `f`, type `Mix` and press
   `Enter`.
5. Press `c`, type `100` and press `Enter`. The reverb now gives only the
   reverb sound, not the dry sound.
6. Press `<Space>d` to hide the panel.

## Send the tracks

1. Go to the first track that needs reverb.
2. Press `<Space>s`. Type `Reverb` and press `Enter`. The track now sends to the
   reverb track at -12 dB.
3. Go to the next track, and do step 2 again.

To give the level when you send, type the command: `:send Reverb -9`.
Then press `j@:` to send the next track the same way. To send many tracks
in one step, select them with `V` and `j`, then type `:send Reverb -9`.

To change the level of a send, type the command again with the new level:
`:send Reverb -6`.

## Set the amount of reverb

- To change the reverb on one track, change its send. Press `<Space>m`, go to
  the strip of the track, and press `k` until the send row is selected.
  Press `+` or `-` to change the send by one dB.
- To change the reverb on all the tracks, move the fader of the reverb
  track.
- To remove a send, select the send row in the mixer and press `x`. You
  can also type `:send.remove Reverb` on the track.

To send the sound before the fader, so that the send does not change when
the fader moves, type `:send Reverb -9 pre=1`.

In the graphical window, click + Send above the devices of the track.
