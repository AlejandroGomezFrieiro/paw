# About groups and VCAs

paw builds the structure of a large mix from usual tracks with data in
their `meta`, and it adds no new kinds of objects for it. A mix of many
tracks needs structure, e.g., a bus for the drums, one fader for all the
strings, and a way to work on one part alone. The page explains why paw
does it with usual tracks. For the commands, see
[Routing](../reference/routing.md), [Narrowed tabs](../reference/narrowing.md)
and [Frozen tracks](../reference/freezing.md).

## A group is a track

A group is a track that other tracks play into, with a mark in its
`meta`. A group therefore has a fader, a mute and devices like any track,
and save, copy, undo and the views need nothing new for groups. The views
only fold the members into the group and indent them below it.

## A VCA is a fader without sound

A group sums the sound of its members, but sometimes you want to control
the level of tracks that play to different places. A VCA does that, as on
a mixing console. A VCA is also a usual track with a mark, but it has no
devices and plays nothing.

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

## Narrowed tabs

REAPER opens a part of a large project as a subproject in a separate file,
but paw narrows a tab to one group instead. The tab shows only the group,
but it is the same project with one undo tree. An edit in the narrowed tab
is a usual edit, and you can go between the tabs at any time.

While you work on the group, the rest of the song can play, be silent, or
play from rendered files. When it plays from rendered files, its devices
can rest.

## A freeze before the fader

A frozen track plays a rendered file instead of its devices. paw takes the
freeze before the fader, so the fader, pan, mute and sends stay live and
the mix continues around the frozen track. A freeze of a group holds all
its members, because the file of the group already holds their sound.
