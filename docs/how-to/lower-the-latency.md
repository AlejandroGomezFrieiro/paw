# How to lower the latency

<!-- tags: lower-latency crackles -->

You can make the delay between a key and its sound shorter, and you can
fix the sound when it then crackles. A smaller block gives a shorter
delay, but it needs more of the CPU.

## See the current latency

1. Type `:audio`. The top line of the list gives the sound system, the
   sample rate and the block size. It also gives the latency of the input
   and the output, for example `in 5.3 ms · out 5.3 ms`.
2. Press `Esc` to close the list.

## Make the block smaller

1. Type `:audio`, select a smaller block, for example
   `128 frames (2.7 ms)`, and press `Enter`. paw opens the device again
   with that block.
2. Play the song, or play a few notes on a MIDI keyboard.
3. Type `:engine.status`. The message gives the CPU load and the number of
   xruns, which are the blocks that were late.

You can also type `:audio.buffer 128`, and paw keeps the block size for
the next start. To use the block size of the device again, type
`:audio.buffer 0`.

With PipeWire, the block size is a request, and other programs can make
PipeWire use a different size. `:audio` shows the size in use.

## If the sound crackles

1. Type `:engine.status`. If the number of xruns goes up while the song
   plays, the CPU cannot make each block in time.
2. Select the next larger block in `:audio`, first 256 and then 512
   frames.
3. If one heavy part causes the problem, freeze it (see
   [How to freeze a heavy part](freeze-a-heavy-part.md)).
4. Close the editors of plugins that you do not use, because some editors
   use a large part of the CPU.

Use a small block while you record or play live. While you mix, use a
larger block, because the delay is not important then.

If the device is a Bluetooth output, the latency stays high at all block
sizes. Use a cable or an audio interface, as
[How to choose the audio devices](choose-audio-devices.md) shows.

If the recorded takes are late against the song, the block size is not
the cause. See [How to set the recording offset](set-the-recording-offset.md).

## See also

- [Audio devices](../reference/audio-devices.md#latency): the latency, PipeWire.
- [The audio engine](../reference/engine.md): the threads and the xruns.
