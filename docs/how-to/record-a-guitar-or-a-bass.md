# How to record a guitar or a bass

This guide shows you how to record an electric guitar or a bass through an
audio interface. It assumes that you know how to move between tracks and
play the song. For each rule, see [Recording](../reference/recording.md).

## Connect the instrument

1. Connect the instrument to an instrument input of the interface. This
   input is often named "Hi-Z" or "Inst". If the input has a switch, set
   it to the instrument position.
2. Play the loudest part. Turn the gain knob of the interface until the
   level light does not show red.
3. If paw does not use your interface, type `:audio.input UR22`, with a
   part of the name of your interface.

## Prepare the track

1. Press `o` to add a track. To give it a name, press `grn`, type `Guitar`
   and press `Enter`.
2. Press `I`. A list of the inputs opens.
3. Type a part of the name of the input channel, for example `UR22 1`.
   Then press `Enter`. A guitar or a bass uses one channel, not a pair.
4. Press `r` to arm the track. Play. The track header shows the level at
   the input, and you hear the instrument.
5. To tune, type `:tuner`. The device panel shows the tuner, with the note
   and the cents. When you are in tune, press `<Space>dd` to hide the panel.

To play through an amp simulator, press `a` on the track and select the
plugin. paw records the dry sound of the instrument. So you can change the
amp later.

If you hear the instrument late, make the block size smaller: type
`:audio.buffer 128`. If the sound then crackles, use `256`.

## Record

1. Move the cursor to where the take starts.
2. Press `R`. The song plays from the cursor, and the status line shows
   `rec`.
3. Play the part. Press `<Space><Space>` to stop. The take is now a clip on the
   track.

paw writes the file into `media` next to the project. If the project is
not saved, the file goes to `~/.local/share/paw/recordings`. When you save
the project, paw links or copies the file into `media`.

To hear the input when the track is not armed, press `<A-i>`.

If the take is late against the song, set the recording offset (see
[How to set the recording offset](set-the-recording-offset.md)). To record
the same part many times, see
[How to record takes over a loop and comp them](record-takes-and-comp.md).
