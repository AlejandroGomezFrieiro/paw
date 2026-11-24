# How to make and use part templates

You can save a part with its devices and levels, and make the same part
again in other projects. For example, you can save a vocal part with its
EQ and compressor. The `templates` extension does the work, and each
command is in the [templates README](../../extensions/templates/README.md).

## Load the extension

Type `:ext.load templates`. If you want it to load at each start, see
[How to load an extension](load-an-extension.md).

## Save a template

1. Put the cursor on the part.
2. Press `\Ts`, type a name, for example `Lead vocal`, and press `Enter`.
   paw saves the part with its devices, their settings, the level, the
   pan, the color and the input.

To save a group with all its parts, put the cursor on the part of the
group and press `\Ts`.

To save only the devices, as a chain, press `\Tf` and type a name.

## Use a template

1. Put the cursor on a part, because the new part goes below it.
2. Press `\Tl`, type a part of the name, for example `lead`, and press
   `Enter`. The part appears with its devices.

A chain goes onto the end of the devices of the cursor part.

To list the templates, type `:templates`. To delete one, type
`:template.delete Lead vocal`.

A template does not keep the clips of the part, or the parts that the
part sends to.

In the graphical window, choose Part → From a template…, or "Save as a
template…" in the menu of a part.
