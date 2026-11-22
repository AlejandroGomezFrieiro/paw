# How to map a MIDI controller

You can move faders and parameters with the knobs of a MIDI controller.
The steps assume that paw runs with an audio device, so that the MIDI
ports are open (see [MIDI](../reference/midi.md#midi-input)). Each command
is in [MIDI controllers](../reference/learn.md).

## Map a parameter of a device

1. Open the device panel and move the cursor to the parameter.
2. Type `:learn`.
3. Turn the knob on the controller, and the knob then moves the parameter.

In the graphical window, click the plug icon next to the parameter, and
then turn the knob.

## Map the fader of a track

1. Select the track.
2. Type `:learn volume`, or type `:learn pan` for the pan.
3. Move the fader on the controller.

## Map the control that you moved last

1. Move the control in paw, such as a fader or a parameter in the editor
   of a plugin.
2. Type `:learn`.
3. Move the control on the controller.

## Remove a mapping

1. Type `:learn.list`.
2. Select the mapping, and paw removes it.

If the target does not move, turn the knob past its current value,
because paw waits until the control gets to that value.

If you
want the target to jump at once, set `paw.opt.learn_pickup = false` in
`init.lua`.

To record the moves as automation, set the automation mode of the track
first, as [How to write automation with the faders](write-automation-with-the-faders.md)
shows.
