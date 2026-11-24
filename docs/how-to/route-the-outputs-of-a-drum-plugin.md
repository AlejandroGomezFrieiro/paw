# How to route the outputs of a drum plugin

You can give each output of a drum plugin a part of its own, so that you
can mix each drum on its own part. The rules are in
[Routing](../reference/routing.md#instruments-with-several-outputs).

1. Add the drum plugin to a part, open the device panel, and select the
   plugin.
2. Type `:device.spread`. paw makes a part for each output pair that
   plays nowhere, with the name of the pair, and it puts the new parts
   and the drum part in a group.
3. Play the song. Each drum now plays on its own part, and the device line
   shows `outs 6/6`.

To route only one pair, press `O` in the device panel, select the pair,
and then select the part. Or type `:device.output 2 Kick`.

To remove a route, type `:device.output 2 none`.

In the graphical window, use the Outs row on the card of the device.

The built-in `drums` device also has a pair for each family of drums.
