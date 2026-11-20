# How to record vocals with a count-in and a click

This guide shows you how to record a voice with the metronome in your
headphones. The metronome also counts one bar before the take. It assumes that your
microphone is connected to the audio interface. For each rule, see
[Recording](../reference/recording.md).

## Prepare the track

1. If the microphone is a condenser microphone, switch on the phantom
   power (+48V) of the interface.
2. Sing the loudest part. Turn the gain knob of the interface until the
   level light does not show red.
3. In paw, press `o` to add a track. Press `grn`, type `Vocal` and press
   `Enter`.
4. Press `I`. Type a part of the name of the microphone input, for example
   `UR22 1`, and press `Enter`.
5. Press `r` to arm the track. Sing. The track header shows the level at
   the input.

Use closed headphones, not loudspeakers. Then the microphone does not
record the click.

## Add the click and the count-in

1. Press `gm` to start the metronome. The status line shows `click`.
2. Type `:countin 1` to count one bar before the take. For two bars, type
   `:countin 2`.

## Record

1. Move the cursor to where the take starts.
2. Press `R`. The metronome counts one bar, and the status line shows
   `count`. The playhead does not move during the count.
3. Sing after the count. The song plays, and paw records.
4. Press `<Space><Space>` to stop. The take is a clip that starts at the
   cursor, not at the start of the count.

To record the same lines many times, see
[How to record takes over a loop and comp them](record-takes-and-comp.md).
For more about the click, see
[How to use the metronome](use-the-metronome.md).
