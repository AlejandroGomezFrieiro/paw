# How to name, color, reorder and group parts

<!-- tags: organize-parts folders -->

You can keep the parts of a song in order by giving them names and
colors, changing their order, and putting them in groups. A group in paw
is a folder and a bus at the same time. Its fader, mute and devices act on
all of its parts.

## Name a part

1. Put the cursor on the part.
2. Press `grn`, and a prompt shows the name of the part.
3. Press `Ctrl-u` to clear the name, type the new name, and press `Enter`.

## Color a part

1. Put the cursor on the part.
2. Press `grC`, and the list of the colors of the theme opens.
3. Select a color, for example `coral`, and press `Enter`.
   The header, the clips and the notes of the part take that color.

To give the part the color of the theme again, select `none`.

## Reorder the parts

To move the part down, press `<A-j>`, and to move it up, press `<A-k>`.
A count moves it more places, so `3<A-j>` moves it down three parts.

## Group parts into a folder

1. Put the cursor on the first part of the group.
2. Press `V`, and then `j` until the selection holds all the parts.
3. Press `<Space>tg`, type the name of the group, for example `Drums`, and
   press `Enter`. The group part shows above its parts, which are
   indented.
4. To fold the group, put the cursor on the group part and press `za`.
   Press `za` again to open it. The fold is in this window only, and it is
   not an undo step.

To put one more part into the group, type `:part.into Drums` on that
part. To take a part out of its group, press `<Space>tG`.

To work on one group alone, press `znn` on the group, as
[How to work on one group of a large project](work-on-one-group.md) shows.

In the graphical window, you can use the mouse:

- Double-click a part header to rename it.
- Drag a header up or down to move the part, or drop it among the parts
  of a group to put it into the group.
- Use the right-click menu of a header for the color and the group
  entries.

## See also

- [Routing](../reference/routing.md): groups, VCAs, sends.
- [About groups and VCAs](../explanation/about-groups-and-vcas.md)
