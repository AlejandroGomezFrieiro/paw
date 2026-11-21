# How to work on one group of a large project

This guide shows you how to see and edit only one group of a large
project. For each rule, see
[Narrowed tabs](../reference/narrowing.md).

1. Move the cursor to the header of the group, or to one of its tracks.
2. Press `zn`. A new tab opens with the group and its tracks only. The
   status line shows `Song › Strings`.
3. Edit, mix and add tracks as usual. A new track goes into the group.
4. To hear only the group, type `:set scope_rest=mute`.
5. To return to the full project, press `zw`.

To go between the narrowed tab and the full project, press `gt`. The
narrowed tab stays open.

If the rest of the song uses much CPU, type `:set scope_rest=frozen`. paw
renders the rest in the background and plays the files.

To narrow to a group by name, type `:narrow Strings`.

For one section, see [How to work on one section of a song](work-on-one-section-of-a-song.md).
