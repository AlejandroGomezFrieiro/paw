# How to work on one group of a large project

This guide shows you how to see and edit only one group of a large
project. For each rule, see
[Scopes](../reference/narrowing.md).

1. Move the cursor to the header of the group, or to one of its tracks.
2. Press `znag`. The window shows the group and its tracks only. The
   status line shows `Song › Strings`.
3. Edit, mix and add tracks as usual. A new track goes into the group.
4. To hear only the group, type `:set scope_rest=mute`.
5. To return to the full project, press `zw`.

To see the full project beside the group, press `<Space>zv` on the group
in place of `znag`. The new window shows the group, and the first window
shows the full project. To show the group in a tab of its own, press
`<Space>zt`.

If the rest of the song uses much CPU, type `:set scope_rest=frozen`. paw
renders the rest in the background and plays the files.

To narrow to a group by name, type `:narrow Strings`.

For one section, see [How to work on one section of a song](work-on-one-section-of-a-song.md).
