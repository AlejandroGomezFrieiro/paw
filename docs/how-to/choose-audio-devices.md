# How to choose the audio devices

<!-- tags: audio-devices -->

You can choose the audio output, the audio input and the block size that
paw uses. Until you choose, paw opens the default output and input of the
system.

## Choose in paw

1. Type `:audio`, and a list shows each output, input, block size, sample
   rate and sound system.
2. Select a line and press `Enter`.

In the graphical window, click the engine indicator at the right of the
transport bar.

To choose one device by name, type a part of its name, as in
`:audio.output UR22` or `:audio.input UR22`. To open the default of the
system again, type `:audio.output default`.

To change the block size or the sample rate, type `:audio.buffer 128` or
`:audio.rate 48000`. The value `0` gives the device's own value.

## Choose when paw starts

Give the devices on the command line, by a part of their names:

```sh
paw --output UR22 --input UR22
```

To start without an audio input, add `--no-input`.

## Choose in your configuration

Put the following line in `~/.config/paw/init.lua`:

```lua
paw.audio.use({ output = "UR22mkII Stereo", input = "UR22mkII", buffer = 128 })
```

## What paw remembers

A choice that you make in paw belongs to the computer and not to the
project. paw keeps it in `~/.local/state/paw/audio.json` and opens the
same devices at the next start. If a remembered device is not plugged in,
paw opens the default device and shows a message.

## See also

- [How to lower the latency](lower-the-latency.md): a smaller block, and what to do when the sound crackles.
- [How to start paw the first time and hear sound](start-paw-and-hear-sound.md): check the device and hear a test tone.
- [The programs and their options](../reference/programs.md): `--audio`, `--rate`, `--buffer` and the other options.
- [Files that paw keeps](../reference/state-files.md).
