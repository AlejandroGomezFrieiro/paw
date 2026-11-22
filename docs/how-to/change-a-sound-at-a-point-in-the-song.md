# How to change a sound at a point in the song

<!-- tags: state-lane-howto change-preset-in-song change-amp-model-in-song -->

You can change the sound of a plugin at a point in the song. For example,
you can have a clean amp in the verse and a crunch amp in the chorus. The sound
can be a preset, an amp model or the full state of the plugin. You hear
the change as the song plays, and a rendered file has it on the exact
frame.

The steps assume a track with the plugin on it.

## Keep the first sound

1. Put the cursor on the track and press `<Space>al`, and a list of what
   to automate opens. Type `state` and press `Enter`. A row for the state
   lane of the plugin opens under the track, and the cursor is on it.
2. Set the plugin to the first sound, in its window, with its preset, or
   with the keys of the device panel.
3. Press `0` to go to the start, and press `\s`. The lane keeps the sound
   as the state `A`, from the start.

## Change to a second sound

1. Set the plugin to the second sound.
2. On the lane's row, move the cursor to the point where the sound
   changes, for example with `w` or `l`.
3. Press `\s`. The lane keeps the sound as the state `B`, from the
   cursor, and the row shows `A` and `B` where each one starts.
4. Press `<Space><Space>` to play from the start. The first sound plays up to the
   point, and the second sound plays from it.

To give a point another state, put the cursor on the point and press `c`,
and a list of the states opens. To remove a point, press `x`.

## Change an amp model or a preset by its name

With the `plugstate` extension, you do not need to set the plugin by hand.
Move the cursor to the point and type `:plugstate.at` and words of the
name, for example `:plugstate.at bogner`. The plugin's state lane then
gives that preset or model from the cursor. `:plugstate.at snapshot=B`
gives a snapshot. The details are in
[How to switch amp models and presets from paw](switch-amp-models-and-presets.md).

## Make sure that a rendered file has the change

Render the song as [How to export a song](export-a-song.md) shows. The
rendered file changes on the frame of each point, even for a plugin that
loads its model in the background. For such a plugin, paw waits until the
plugin is ready, and then it renders the frames after the point.

If an instrument stops its notes at the point, put the point a little
before the notes. The details are in
[Automation](../reference/automation.md#state-lanes).
