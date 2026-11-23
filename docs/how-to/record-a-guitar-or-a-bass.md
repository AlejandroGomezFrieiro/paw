# How to record a guitar or a bass

You can record an electric guitar or a bass through an audio interface.
The steps assume that you know how to move between tracks and play the
song, and the rules are in [Recording](../reference/recording.md).

## Plug in the instrument

1. Plug the instrument into an instrument input of the interface, which is
   often named "Hi-Z" or "Inst". If the input has a switch, set it to the
   instrument position.
2. Play the loudest part, and turn the gain knob of the interface until
   the level light does not show red.
3. If paw does not use your interface, type `:audio.input UR22`, with a
   part of the name of your interface.

## Prepare the track

1. Press `o` to add a track. To give it a name, press `grn`, type `Guitar`
   and press `Enter`.
2. Press `I`, and a list of the inputs opens. Type a part of the name of
   the input channel, for example `UR22 1`, and press `Enter`. A guitar or
   a bass uses one channel, not a pair.
3. Press `r` to arm the track, and play. The track header shows the level
   at the input, and you hear the instrument.
4. To tune, type `:tuner`, and the device panel shows the tuner with the
   note and the cents. When you are in tune, press `<Space>dd` to hide the
   panel.

To play through an amp simulator, press `a` on the track and select the
plugin. paw records the dry sound of the instrument, so you can change the
amp later.

If you hear the instrument late, make the block size smaller with
`:audio.buffer 128`. If the sound then crackles, use `256`.

## Record

1. Move the cursor to where the take starts.
2. Press `R`. The song plays from the cursor, and the status line shows
   `rec`.
3. Play the part, and press `<Space><Space>` or `Esc` to stop. The take is
   now a clip on the track, and the message line names it, for example
   `recording stopped: take 1 kept (u removes it)`.

`Esc` first cancels what you were doing, such as a selection. If you
selected something while you recorded, press `Esc` two times. `Esc` stops
the song only while paw records.

paw writes the file into `media` next to the project. If the project is
not saved, the file goes to `~/.local/share/paw/recordings`, and when you
save the project, paw links or copies the file into `media`.

To hear the input when the track is not armed, press `<A-i>`.

If the take is late against the song, set the recording offset (see
[How to set the recording offset](set-the-recording-offset.md)). To record
the same part many times, see
[How to record takes over a loop and comp them](record-takes-and-comp.md).
