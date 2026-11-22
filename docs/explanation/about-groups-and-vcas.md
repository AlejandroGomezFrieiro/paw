# About groups and VCAs

A mix of many tracks needs structure. For example: a bus for the drums,
one fader for all the strings, and a way to work on one part alone. paw gives
this structure with usual tracks and data in their `meta`, not with new
kinds of objects. This page tells why. For the commands, see
[Routing](../reference/routing.md), [Scopes](../reference/narrowing.md)
and [Frozen tracks](../reference/freezing.md).

## A group is a track

A group is a track that other tracks play into, with a mark in its
`meta`. So a group has a fader, a mute and devices, as any track. Save,
copy, undo and the views need nothing new for groups. The views only fold
the members into the group, and indent them below it.

## A VCA is a fader without sound

A group sums the sound of its members. Sometimes you want to control the
level of tracks that play to different places. A VCA does this, as on a
console. A VCA is also a usual track with a mark, but it has no
devices and plays nothing.

The engine does not know VCAs. The sync adds the fader and the lanes of
each VCA into the gain and the lane of each member, in dB. The audio
thread then plays one lane for each member, sample by sample. So a VCA
costs nothing on the audio thread, and a render sounds the same as
playback.

## Linked faders

A group can also link the faders of its members: a move of one fader moves
the others by the same number of dB. This keeps the balance, as a VCA does,
but without a separate fader. The fader of the group itself does not move,
because it already acts on the sum.

## Narrowed windows

REAPER opens a part of a large project as a subproject, in a separate
file. paw narrows a window to one group instead. The window sees only the
group, but it is the same project, with one undo tree. So an edit in the
narrowed window is a usual edit. A split can show the whole song beside
the group, and `zw` returns at any time. While you work on the group, the rest of the song can play, be
silent, or play from rendered files. The last choice lets its devices
rest.

## A freeze before the fader

A frozen track plays a rendered file instead of its devices. paw takes
the freeze before the fader, so the fader, pan, mute and sends stay live,
and the mix continues around the frozen track. A freeze of a group holds
all its members, because the file of the group already holds their sound.
