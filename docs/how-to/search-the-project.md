# How to search the project and go through the results

<!-- tags: search-guide -->

This guide shows you how to find each place in a song with a text or a
kind of note. It also shows how to go from one place to the next. paw
puts the places in the quickfix list, as Vim does. To find a track by
its name, see [How to find a track by name](find-a-track-clip-or-marker.md).

## Find a text anywhere

1. Type `:vimgrep /pizz/`. paw finds every text that holds `pizz`: names
   of tracks, clips, markers and devices, lyrics, articulations and
   comments. The cursor goes to the first place.
2. Press `]q` to go to the next place, and `[q` to go to the place
   before.
3. To see all the places, type `:copen`. A list opens at the bottom.
   Press `Enter` on a line to go there, and `q` to close the list.

To find only the lyrics, type `:vimgrep /la/ lyric`.

To see the places in a list that filters while you type, press `<Space>fg`.

## Find notes

Press `<Space>fN`. The list shows each note of the project, with its pitch, its
lyric and its articulation. Type, for example, `c5` or a word of a lyric,
and press `Enter` to go to the note.

## Find by a rule

A query finds things by what they are and where they are:

- `:query note[pitch>=c6]` lists every note from C6 up.
- `:query clip:has(note[vel>120])` lists the clips with a note louder than velocity 120.
- `:select clip[name~=verse]` selects every clip with `verse` in its
  name. Then an operator acts on all of them, for example `d`.

Each query puts its results in the quickfix list, so `]q` and `[q` go
through them.

## Change every place

To act on each place in the list, type `:cdo` and a command. For example,
`:vimgrep /^Viol/ track` then `:cdo track.mute` mutes every track whose
name starts with `Viol`. It is one undo step.

## See also

- [Search the text of the project](../reference/grep.md): `:vimgrep` and its fields.
- [Structural queries](../reference/queries.md): the syntax of a query.
- [The quickfix list](../reference/quickfix.md): the list and its commands.
