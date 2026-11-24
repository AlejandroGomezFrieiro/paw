# About groups and VCAs

paw builds the structure of a large mix from usual parts with data in
their `meta`, and it adds no new kinds of objects for it. A mix of many
parts needs structure, e.g., a bus for the drums, one fader for all the
strings, and a way to work on one part alone. The page explains why paw
does it with usual parts. For the commands, see
[Routing](../reference/routing.md), [Scopes](../reference/narrowing.md) and [Frozen
parts](../reference/freezing.md).

## A group is a part

A group is a part that other parts play into, with a mark in its
`meta`. A group therefore has a fader, a mute and devices like any part,
and save, copy, undo and the views need nothing new for groups. The views
only fold the members into the group and indent them below it. Each
member names its group in its field `parent`. A group can be in another
group, to any depth, and paw refuses a move that would put a group
inside itself.

Whether a group is folded is part of the window, not of the project, as
folds are in Vim. Two windows can show the same group folded and open,
and a fold is not an undo step, so `u` never opens a group that you
folded. The project still keeps the folds of each window with its
windows, so they come back when you open it. The same reason makes any
set of parts a fold, with `zf`, because a fold is a way to show the
parts and not one of them. See [Folds](../reference/narrowing.md#folds).

## A VCA is a fader without sound

A group sums the sound of its members, but sometimes you want to control
the level of parts that play to different places. A VCA does that. A VCA
is also a usual part with a mark, but it has no devices and plays
nothing.

The engine does not know about VCAs. When paw syncs the project to the
engine, it adds the fader and the lanes of each VCA into the gain and the
lane of each member, in dB. The audio thread then plays one lane for each
member, sample by sample, so a VCA costs nothing on the audio thread and a
render sounds the same as playback.

## Linked faders

A group can also link the faders of its members, so a move of one fader
moves the others by the same number of dB. Linked faders keep the balance
like a VCA does, but without a separate fader. The fader of the group
itself does not move, because it already acts on the sum.

## Narrowed windows

To work on a part of a large project, paw narrows a window to one group.
The window shows only the group, but it is the same project with one undo
tree. An edit in the narrowed window is a usual edit, a split can show the
whole song beside the group, and `zw` returns at any time.

While you work on the group, the rest of the song can play, be silent, or
play from rendered files. When it plays from rendered files, its devices
can rest.

## A freeze before the fader

A frozen part plays a rendered file instead of its devices. paw takes the
freeze before the fader, so the fader, pan, mute and sends stay live and
the mix continues around the frozen part. A freeze of a group holds all
its members, because the file of the group already holds their sound.
