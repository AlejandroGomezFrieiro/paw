# How to add an audio track for a microphone or a guitar

<!-- tags: audio-track -->

You can add a track for a microphone or a guitar that is plugged into
your audio interface, and you can hear the input through paw while you
play. The steps assume that paw uses your interface as its input. If it
does not, type `:audio.input UR22`, with a part of the name of your
interface.

1. In the arrange view, press `o` to add a track. Then press `grn`, type a
   name, for example `Guitar`, and press `Enter`.
2. Choose the input of the track:
   1. Press `I`, and the list of the inputs of the track opens.
   2. Under audio, select the channel where the instrument is plugged in,
      for example `UR22mkII · 1`, and press `Enter`.
      For a stereo source, such as a keyboard with two outputs, select a pair: `UR22mkII · 1/2`.
3. Play or sing. The header of the track shows the level at the input.
4. Press `<A-i>` to switch the monitor on, and you hear the input through
   the devices of the track.

In place of step 2, you can also type `:track.input 1` or
`:track.input 1/2`.

**CAUTION:** Use headphones when you monitor a microphone, because
speakers near the microphone can make a loud feedback tone.

If the level is too low or touches the red, change the gain on the
interface and not the fader of the track. The fader does not change what
paw records.

## Add an amp or an effect

1. Press `a`, and the list of devices opens.
2. Type a part of the name, for example `reverb` or the name of an amp
   plugin, and press `Enter`.

paw records the input before it goes through the devices, so you can
change the amp after the recording.

## Record

Press `r` to arm the track, and press `R` to record. The full steps are in
[How to record a guitar or a bass](record-a-guitar-or-a-bass.md).

In the graphical window, the input button on the track header opens the
same list, and the loudspeaker next to it switches the monitor.

## See also

- [Recording](../reference/recording.md#the-input-of-a-track): inputs, monitoring, arming.
- [How to lower the latency](lower-the-latency.md): when you hear the input late.
