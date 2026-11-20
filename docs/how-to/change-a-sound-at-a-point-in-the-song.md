# How to change a sound at a point in the song

<!-- tags: state-lane-howto change-preset-in-song change-amp-model-in-song -->

This guide shows you how to change the sound of a plugin at a point in
the song. The sound can be a preset, an amp model or the full state of
the plugin. An example is a clean amp in the verse and a crunch amp in
the chorus. You hear the change as the song plays. A rendered file has it
on the exact frame.

The guide assumes a track with the plugin on it.

## Keep the first sound

1. Put the cursor on the track and press `<Space>al`. A list of what to
   automate opens.
2. Type `state` and press `Enter`. A row for the state lane of the plugin
   opens under the track, and the cursor is on it.
3. Set the plugin to the first sound: in its window, with its preset, or
   with the keys of the device panel.
4. Press `0` to go to the start, and press `\s`. The lane keeps the sound
   as the state `A`, from the start.

## Change to a second sound

1. Set the plugin to the second sound.
2. On the lane's row, move the cursor to the point where the sound
   changes, for example with `w` or `l`.
3. Press `\s`. The lane keeps the sound as the state `B`, from the
   cursor. The row shows `A` and `B` where each starts.
4. Press `<Space><Space>` to play from the start. The first sound plays up to the
   point, and the second sound plays from it.

To give a point another state, put the cursor on the point and press `c`.
A list of the states opens. To remove a point, press `x`.

## Change an amp model or a preset by its name

With the `plugstate` extension, you do not set the plugin by hand. Move
the cursor to the point and type `:plugstate.at` and words of the name.
For example, `:plugstate.at bogner`. The plugin's state lane gives that
preset or model from the cursor. `:plugstate.at snapshot=B` gives a
snapshot. See
[How to switch amp models and presets from paw](switch-amp-models-and-presets.md).

## Make sure that a rendered file has the change

Render the song: see [How to export a song](export-a-song.md). The
rendered file changes on the frame of each point. This is also true for a
plugin that loads its model in the background. paw waits until the plugin
is ready, then it renders the frames after the point.

If an instrument stops its notes at the point, put the point a little
before the notes. For the details, see
[Automation](../reference/automation.md#state-lanes).
