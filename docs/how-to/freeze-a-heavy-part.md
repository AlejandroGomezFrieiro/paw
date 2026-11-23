# How to freeze a heavy part

You can stop the CPU use of a heavy instrument and continue to mix, by
freezing its part. The rules are in
[Frozen parts](../reference/freezing.md).

1. Move the cursor to the part, or to the header of a group.
2. Type `:freeze`. paw renders the part and plays the file, and the
   header shows `F`.
3. Continue to mix. The fader, pan, mute and sends of the part still
   work.
4. To change the notes or the devices, type `:unfreeze`, edit, and then
   type `:freeze` again.

If you edit a frozen part, paw asks if it must unfreeze the part.
If you answer no, paw keeps the edit, and you hear it after `:unfreeze`.
Press `K` on the part to see if its file is up to date, or which part
changed since you froze it.

If the sound has a long tail, add `tail=6` for six seconds after the end.

If you change the tempo, type `:unfreeze` and then `:freeze`, because paw
does not render the file again by itself.

To freeze several parts, give a range: `:t2,t4freeze`.

If you also want to render the fader and the pan, use `:bounce`
instead. It makes a new audio part and mutes the original part.
