# How to record vocals with a count-in and a click

You can record a voice with the metronome in your headphones, and the
metronome can also count one bar before the take. The steps assume that
your microphone is plugged into the audio interface, and the rules are in
[Recording](../reference/recording.md).

## Prepare the track

1. Prepare the interface:
   - If the microphone is a condenser microphone, switch on the phantom
     power (+48V) of the interface.
   - Sing the loudest part, and turn the gain knob of the interface until
     the level light does not show red.
2. In paw, press `o` to add a track. Press `grn`, type `Vocal` and press
   `Enter`.
3. Press `I`, type a part of the name of the microphone input, for example
   `UR22 1`, and press `Enter`.
4. Press `r` to arm the track, and sing. The track header shows the level
   at the input.

Use closed headphones and not loudspeakers, so that the microphone does
not record the click.

## Add the click and the count-in

1. Press `gm` to start the metronome, and the status line shows `click`.
2. Type `:countin 1` to count one bar before the take. For two bars, type
   `:countin 2`.

## Record

1. Move the cursor to where the take starts.
2. Press `R`. The metronome counts one bar, and the status line shows
   `count`. The playhead does not move during the count.
3. Sing after the count, while the song plays and paw records.
4. Press `<Space><Space>` or `Esc` to stop. The take is a clip that starts
   at the cursor, not at the start of the count.

If you press `Esc` during the count, paw calls the take off and records
nothing.

To record the same lines many times, see
[How to record takes over a loop and comp them](record-takes-and-comp.md).
More about the click is in
[How to use the metronome](use-the-metronome.md).
