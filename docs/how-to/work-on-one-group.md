# How to work on one group of a large project

You can see and edit only one group of a large project, in a narrowed tab.
The rules are in [Narrowed tabs](../reference/narrowing.md).

1. Move the cursor to the header of the group, or to one of its tracks,
   and press `zn`. A new tab opens with the group and its tracks only, and
   the status line shows `Song › Strings`.
2. Edit, mix and add tracks as usual. A new track goes into the group.
3. If you want to hear only the group, type `:set scope_rest=mute`.
4. To return to the full project, press `zw`.

To go between the narrowed tab and the full project, press `gt`, and the
narrowed tab stays open.

If the rest of the song uses much CPU, type `:set scope_rest=frozen`, and
paw renders the rest in the background and plays the files.

To narrow to a group by name, type `:narrow Strings`.

For one section, see [How to work on one section of a song](work-on-one-section-of-a-song.md).
