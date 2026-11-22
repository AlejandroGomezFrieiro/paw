# How to name, color, reorder and group tracks

<!-- tags: organize-tracks folders -->

You can keep the tracks of a song in order by giving them names and
colors, changing their order, and putting them in groups. A group in paw
is a folder and a bus at the same time. Its fader, mute and devices act on
all of its tracks.

## Name a track

1. Put the cursor on the track.
2. Press `grn`, and a prompt shows the name of the track.
3. Press `Ctrl-u` to clear the name, type the new name, and press `Enter`.

## Color a track

1. Put the cursor on the track.
2. Press `grC`, and the list of the colors of the theme opens.
3. Select a color, for example `coral`, and press `Enter`.
   The header, the clips and the notes of the track take that color.

To give the track the color of the theme again, select `none`.

## Reorder the tracks

To move the track down, press `<A-j>`, and to move it up, press `<A-k>`.
A count moves it more places, so `3<A-j>` moves it down three tracks.

## Group tracks into a folder

1. Put the cursor on the first track of the group.
2. Press `V`, and then `j` until the selection holds all the tracks.
3. Press `<Space>tg`, type the name of the group, for example `Drums`, and
   press `Enter`. The group track shows above its tracks, which are
   indented.
4. To fold the group, put the cursor on the group track and press `za`.
   Press `za` again to open it.

To put one more track into the group, type `:track.into Drums` on that
track. To take a track out of its group, press `<Space>tG`.

To work on one group alone, press `znn` on the group, as
[How to work on one group of a large project](work-on-one-group.md) shows.

In the graphical window, you can use the mouse:

- Double-click a track header to rename it.
- Drag a header up or down to move the track, or drop it among the tracks
  of a group to put it into the group.
- Use the right-click menu of a header for the color and the group
  entries.

## See also

- [Routing](../reference/routing.md): groups, VCAs, sends.
- [About groups and VCAs](../explanation/about-groups-and-vcas.md)
