# How to work on one section of a song

<!-- tags: work-on-a-section narrow region -->

You can see, edit and loop only one section of a song, for example the
bridge, in a narrowed window. The section is a region, and the rules are in
[Scopes](../reference/narrowing.md).

## Narrow to a region

1. If the song has no region, make one. Press `v`, move the cursor over
   the bars of the section, press `<Space>rn` and type a name, for example
   `Bridge`. The details are in
   [How to loop a part of the song](loop-a-part-of-the-song.md#loop-a-region).
2. Type `:narrow Bridge`. The window shows the time of the region and
   every track in it, and the status line shows `Song › Bridge`. With the
   cursor in the region, `znar` does the same.
3. Work in the section:
   - The cursor stays in the time of the section. `0` goes to its start,
     and `$` to its end.
   - The bars count from 1 at the start of the section, in the meter of
     the song, and a second row of the ruler shows the bars of the song.
     The bars that you type are the bars of the section, so `3|` and `:3`
     go to bar 3 of the section.
   - Press `<Space><Space>`, and the playhead loops over the section while
     the window is in front.
   - Edit as usual. The narrowed window changes nothing in the project, and
     undo works in any window.
4. To return to the whole song, press `zw`, and the loop that you had
   returns.

## Narrow to a group and a region

To see only some tracks of the section, narrow again in the same window. For
example, after `:narrow Bridge`, type `:narrow Strings` to see the strings
in the time of the bridge. The status line then shows
`Song › Bridge › Strings`.

- `zw` goes up one level, and `zW` goes up to the whole song.
- `]z` goes to the next region, and `[z` to the region before.
- If the group has no track in the section, paw does not narrow, and the
  message gives the reason.

## Change the bar numbers and the loop

- To see the bars of the song on the ruler in place of the bars of the
  section, type `:set scopebars=song`. `local` gives only the bars of the
  section, and `both` is the default.
- To keep the loop that you had, type `:set noscopeloop`.

## See also

- [How to work on one group of a large project](work-on-one-group.md)
- [Markers and regions](../reference/markers.md)
