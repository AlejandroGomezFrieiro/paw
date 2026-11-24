# How to fix no sound

You can find why you hear nothing when the song plays by checking the
output device, the parts and the system, in that order. The audio devices
are described in [Audio devices](../reference/audio-devices.md).

## Check the output device

1. Type `:engine`. The message names the sound system and the output
   device, for example `pipewire: UR22mkII Stereo, 48000 Hz`.
2. If the message starts with `null`, paw has no output device. paw uses
   `null` when it cannot open a device at the start, or when you start it
   with `--audio null`.
3. Type `:audio`, select the output that your speakers or headphones are
   plugged into, and press `Enter`.
4. If a message says that paw lost the device, plug the device in again,
   and paw opens it again by itself. To try at once, type
   `:audio.reconnect`.

To use the default output of the system, type `:audio.output default`.

## Check the parts

1. Look at the chips `M` and `S` on the part headers. A lit `M` mutes the
   part, and a lit `S` on a different part silences the other parts.
   To unmute all the parts, type `:t* unmute`. To remove all the solos,
   type `:t* unsolo`.
2. Look at the fader of each part and of the master. To set a fader to
   0 dB, put the cursor on the part, press `grv`, type `0` and press
   `Enter`.
3. A MIDI part needs an instrument, and the part header names its
   devices. If a MIDI part has no instrument, press `a` and add one, for
   example `Synth`.
4. If a device on the part is stopped, see
   [How to deal with a plugin that crashes or hangs](deal-with-a-plugin-that-crashes.md).

## Check the system

- Make sure that the volume of your audio interface and of the system is
  up, and that no other program has the device for itself.
- In a shell, type `paw doctor`. It checks the sound system, the devices
  and the plugins, and prints a report.
