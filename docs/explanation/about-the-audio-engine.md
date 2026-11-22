# About the audio engine

The audio engine must give a block of sound on time, each time, because a
late block is a dropout that the listener hears. The page explains how the
engine of paw uses many cores and stays on time, and how it protects the
mix from a bad device. For the commands and fields, see
[The audio engine](../reference/engine.md). For the place of the engine in
paw, see [About the architecture](about-the-architecture.md).

## Many cores and one result

The engine processes the tracks on a pool of worker threads, with one
thread for each core. Tracks that do not depend on each other run at the
same time, and a track that sends, keys or plays into another track runs
before that track.

A render must give the same file each time, so each worker treats denormal
numbers as zero, as the audio thread does, and a track sounds the same on
any thread. A render is the same to the bit with one thread or with
sixteen. The workers take work with one atomic operation, and they do not
allocate memory or take locks.

The workers get the real-time priority of the audio thread, and if the
system refuses that priority, the engine does not use the workers. A worker
without real-time priority can wait behind any other program, and the
audio thread would then wait for the worker. One thread that is on time is
better than many threads that are late.

## Delay compensation

Some devices look ahead, e.g., a limiter must see a peak before the peak
arrives. Such a device delays its output and reports the delay. If one path
to the master has a limiter and another path does not, the two paths do
not line up. paw therefore delays each other path by the difference,
through buses, sends, side-chains and output pairs, so all the sound
arrives together. A render removes the total delay from the start of the
file.

## A device that fails

A device can panic, or it can output NaN or infinity. One bad sample can
make a filter unstable, and a NaN in a bus can silence the master, so paw
guards each device on the audio thread. A device that panics stops, and
the chain ignores it after that. A sample that is not a number becomes
silence at the output of the device, before it gets to a fader or a meter,
and the rest of the mix continues to play.

A plugin can also crash its process, and
[About the plugin sandbox](about-the-plugin-sandbox.md) explains what paw
does then.

## Long files from the disk

A recording of one hour takes gigabytes of memory when it is decoded, so
paw decodes such a file one time into a cache on the disk and maps the
cache into memory. The system reads the pages when the engine needs them,
and it releases them when memory is low. The kernel asks for the next
seconds before the playhead, so the audio thread never waits for the disk.
The decoded sound stays in the cache between runs, so the second time you
open the file it is ready at once.
