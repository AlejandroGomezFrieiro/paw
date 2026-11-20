# How to make and use track templates

This guide shows you how to save a track with its devices and levels. You
can then make the track again in other projects. For example, save a vocal
track with its EQ and compressor. The `templates` extension does this. For
each command, see the [templates README](../../extensions/templates/README.md).

## Load the extension

Type `:ext.load templates`. To load it at each start, see
[How to load an extension](load-an-extension.md).

## Save a template

1. Put the cursor on the track.
2. Press `\Ts`. Type a name, for example `Lead vocal`, and press `Enter`.
   paw saves the track with its devices, their settings, the level, the
   pan, the color and the input.

To save a group with all its tracks, put the cursor on the track of the
group and press `\Ts`.

To save only the devices, as a chain, press `\Tf` and type a name.

## Use a template

1. Put the cursor on a track. The new track goes below it.
2. Press `\Tl`. Type a part of the name, for example `lead`, and press
   `Enter`. The track appears with its devices.

A chain goes onto the end of the devices of the cursor track.

To list the templates, type `:templates`. To delete one, type
`:template.delete Lead vocal`.

A template does not keep the clips of the track. It also does not keep
the tracks that the track sends to.

In the graphical window, choose Track → From a template…, or "Save as a
template…" in the menu of a track.
