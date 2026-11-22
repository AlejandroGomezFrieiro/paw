# How to freeze a heavy track

You can stop the CPU use of a heavy instrument and continue to mix, by
freezing its track. The rules are in
[Frozen tracks](../reference/freezing.md).

1. Move the cursor to the track, or to the header of a group.
2. Type `:freeze`. paw renders the track and plays the file, and the
   header shows `F`.
3. Continue to mix. The fader, pan, mute and sends of the track still
   work.
4. To change the notes or the devices, type `:unfreeze`, edit, and then
   type `:freeze` again.

If you edit a frozen track, paw asks if it must unfreeze the track.
If you answer no, paw keeps the edit, and you hear it after `:unfreeze`.

If the sound has a long tail, add `tail=6` for six seconds after the end.

If you change the tempo, type `:unfreeze` and then `:freeze`, because paw
does not render the file again by itself.

To freeze several tracks, give a range: `:t2,t4freeze`.

If you also want to render the fader and the pan, use `:track.bounce`
instead. It makes a new audio track and mutes the original track.
