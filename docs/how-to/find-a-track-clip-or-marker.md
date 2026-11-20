# How to find a track, a clip or a marker by name

<!-- tags: find-by-name -->

This guide shows you how to move the cursor to a track, a clip or a
marker by its name. A part of the name is enough. In a large song, this is faster
than `j` and `k`.

## Find with `/`

1. In the arrange view, press `/`.
2. Type a part of the name of a clip or a track, for example `verse`, and
   press `Enter`. The cursor goes to the next clip or track with that
   name.
3. Press `n` to go to the next match, and `N` to go to the match before.

To find the next clip with the same name as the clip under the cursor,
press `*`.

## Choose from a list

| To find | Keys |
| --- | --- |
| a track | `<Space>ft` |
| a clip | `<Space>fl` |
| a marker or a region | `<Space>f'` |

1. Press the keys. A list opens, with a preview on the right.
2. Type a part of the name. The list shows only the lines that match.
3. Select the line and press `Enter`. The cursor goes there.

## Go to a marker

- Press `]'` to go to the next marker, and `['` to go to the marker
  before.
- Press `g"` for the list of the markers.
- Type `:marker.goto Chorus` to go to a marker by its name, or
  `:marker.goto 2` by its number.

To put a marker at the cursor, press `g'`. Type its name, for example
`Chorus`, and press `Enter`. If you type no name, paw calls it `Marker 1`,
`Marker 2` and so on. To change the name later, type
`:marker.rename Chorus`.

## See also

- [How to search the project](search-the-project.md): notes, lyrics, and queries.
- [Markers and regions](../reference/markers.md)
- [Pickers](../reference/pickers.md): the keys inside a list.
