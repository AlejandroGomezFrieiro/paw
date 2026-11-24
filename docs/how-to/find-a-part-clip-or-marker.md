# How to find a part, a clip or a marker by name

<!-- tags: find-by-name -->

You can move the cursor to a part, a clip or a marker by its name, and a
part of the name is enough. In a large song, a search by name is faster
than `j` and `k`.

## Find with `/`

1. In the arrange view, press `/`.
2. Type some of the name of a clip or a part, for example `verse`, and
   press `Enter`. The cursor goes to the next clip or part with that
   name.
3. Press `n` to go to the next match, and `N` to go to the match before.

To find the next clip with the same name as the clip under the cursor,
press `*`.

## Choose from a list

| To find | Keys |
| --- | --- |
| a part | `<Space>ft` |
| a clip | `<Space>fc` |
| a marker | `<Space>fm` |
| a region | `<Space>fr` |

1. Press the keys, and a list opens with a preview on the right.
2. Type a part of the name, and the list shows only the lines that match.
3. Select the line and press `Enter`, and the cursor goes there.

## Go to a marker

- Press `]'` to go to the next marker, and `['` to go to the marker
  before. Press `g"` for the list of the markers.
- Type `:marker.goto Chorus` to go to a marker by its name, or
  `:marker.goto 2` to go to it by its number.

To put a marker at the cursor, press `g'`, type its name, for example
`Chorus`, and press `Enter`. If you type no name, paw calls it `Marker 1`,
`Marker 2` and so on. To change the name later, type
`:marker.rename Chorus`.

## See also

- [How to search the project](search-the-project.md): notes, lyrics, and queries.
- [Markers and regions](../reference/markers.md)
- [Pickers](../reference/pickers.md): the keys inside a list.
