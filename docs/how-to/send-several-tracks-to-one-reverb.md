# How to send several tracks to one reverb

You can send several tracks to one reverb on a track of its own, so that
the tracks share one room. The rules are in
[Routing](../reference/routing.md#outputs-and-sends).

## Make the reverb track

1. Put the cursor on the last track, and press `o` to add a track below.
   Press `grn`, type `Reverb` and press `Enter`.
2. Press `a`, type `Reverb` and press `Enter`, and paw puts a reverb on the
   track.
3. Set the reverb to give only the reverb sound, not the dry sound:
   1. Press `<Space>dd` to show the device panel.
   2. Press `f`, type `Mix` and press `Enter`.
   3. Press `c`, type `100` and press `Enter`.
4. Press `<Space>dd` to hide the panel.

## Send the tracks

1. Go to the first track that needs reverb.
2. Press `<Space>ts`, type `Reverb` and press `Enter`. The track now sends
   to the reverb track at -12 dB.
3. Go to the next track, and do step 2 again.

If you want to give the level when you send, type the command, for example
`:send Reverb -9`. Then press `j@:` to send the next track the same way. To send many tracks in one step, select them with `V` and `j`, and
then type `:send Reverb -9`.

To change the level of a send, type the command again with the new level,
for example `:send Reverb -6`.

## Set the amount of reverb

- To change the reverb on one track, change its send. Press `<Space>mm`,
  go to the strip of the track, and press `k` until the send row is
  selected. Then press `+` or `-` to change the send by one dB.
- To change the reverb on all the tracks, move the fader of the reverb
  track.
- To remove a send, select the send row in the mixer and press `x`, or
  type `:send.remove Reverb` on the track.

If you want to send the sound before the fader, so that the send does not
change when the fader moves, type `:send Reverb -9 pre=1`.

In the graphical window, click + Send above the devices of the track.
