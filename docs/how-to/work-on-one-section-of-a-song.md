# How to work on one section of a song

<!-- tags: work-on-a-section narrow region -->

This guide shows you how to see, edit and loop only one section of a song,
for example the bridge. The section is a region. For each rule, see
[Narrowed tabs](../reference/narrowing.md).

## Narrow to a region

1. Make the region, if the song has none. Press `v`, move the cursor over
   the bars of the section, press `<Space>rn` and type a name, for example
   `Bridge`. See [How to loop a part of the song](loop-a-part-of-the-song.md#loop-a-region).
2. Type `:narrow Bridge`. A new tab opens. It shows the time of the region
   and every track in it. The status line shows `Song › Bridge`.
3. The cursor stays in the time of the section. `0` goes to its start, and
   `$` to its end.
4. The bars count from 1 at the start of the section, in the meter of the
   song. A second row of the ruler shows the bars of the song. The bars that
   you type are the bars of the section: `3|` and `:3` go to bar 3 of the
   section.
5. Press `<Space><Space>`. The playhead loops over the section while the tab
   is in front.
6. Edit as usual. Narrowing changes nothing in the project, and undo works
   in any tab.
7. To return to the whole song, press `zw`. The loop that you had returns.

## Narrow to a group and a region

To see only some tracks of the section, narrow again in the same tab. For
example, after `:narrow Bridge`, type `:narrow Strings` to see the strings
in the time of the bridge. The status line shows `Song › Bridge › Strings`.

- `zw` goes up one level, and `:widen!` goes up to the whole song.
- If the group has no track in the section, paw does not narrow. The message
  gives the reason.

## Change the bar numbers and the loop

- To see the bars of the song on the ruler in place of the bars of the
  section, type `:set scopebars=song`. `local` gives only the bars of the
  section, and `both` is the default.
- To keep the loop that you had, type `:set noscopeloop`.

## See also

- [How to work on one group of a large project](work-on-one-group.md)
- [Markers and regions](../reference/markers.md)
