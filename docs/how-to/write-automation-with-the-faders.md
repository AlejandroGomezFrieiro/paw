# How to write automation with the faders

You can record the moves of a fader or a parameter while the song plays.
Each mode is described in [Automation](../reference/automation.md).

1. Select the track and type `:automation touch`. The fader then writes
   only while you move it.
2. Play the song, and move the fader, the pan, or a parameter. You can use
   the keyboard, the graphical window, a MIDI controller, or the editor of
   a plugin. The header shows `T` in red while the track writes.
3. Let go of the control, and the lane controls it again.
4. Stop the song, and type `:automation read` so that later moves write
   nothing.

If you want a control to keep its new value until the song stops, use
`:automation latch`.

To write on all tracks, type `:lane.write`, and each track that is in
`read` mode then latches. Type `:lane.write` again to stop.

To undo a sweep, press `u` one time, because one sweep is one undo step.
