# How to duck a track under the kick

You can make a compressor on the bass react to the kick, which is called a
side-chain. The rules are in
[Routing](../reference/routing.md#side-chains).

1. Select the bass track and type `:device.add compressor`. Then open the
   device panel and select the compressor.
2. Type `:device.sidechain Kick`, or press `gS` and select the kick track.
   The device line shows `key Kick`.
3. Set `threshold` and `ratio` until the bass ducks on each kick.
4. If you want to hear what the detector hears, set `listen` on, and set
   it off again when you are done.

If you want to key the compressor with a kick that you do not hear, mute
the kick and key before its fader: `:device.sidechain Kick pre=1`.

You can duck under a plugin compressor with the same steps, as long as the
plugin has a side-chain input.

To remove the side-chain, type `:device.sidechain none`.

If paw refuses the side-chain, the side-chain makes a loop, for example
when the kick plays into the bass. The message gives the reason.
