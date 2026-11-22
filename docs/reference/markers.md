# Markers and regions

<!-- tags: markers regions -->

A marker is a named place in the song, and a region is a named time range. Both appear on a second row of the ruler (a band of their own in the graphical window), they move with the beats when the tempo changes, and the project saves them. The Lua module is `paw.markers`.

## Keys and commands

| Keys, command | Effect |
| --- | --- |
| `g'` `<Space>rm`, `:marker Chorus` | Put a marker at the cursor. `g'` and `<Space>rm` ask for its name. A marker with no name typed is `Marker 1`, `Marker 2` and so on. |
| `<Space>rn`, `:region Verse` | Make a region over the selection, or over the loop. `<Space>rn` asks for its name. |
| `]'` `['` | Go to the next start of a marker or region, or the one before. You can use them as motions, e.g., `d]'`. |
| `g"`, `:marker.list` | List all markers and regions. Select one to go there. |
| `:marker.goto 3`, `:marker.goto Chorus` | Go to a marker by number or by name. |
| `:marker.rename Bridge` | Rename the marker at the cursor. |
| `:marker.move` | Move the marker at the cursor. |
| `gx` `<Space>rx`, `:marker.remove` | Remove the marker at the cursor, or the one named: `:marker.remove Chorus`. Regions stay. |
| `gX` `<Space>rX`, `:region.remove` | Remove the region that the cursor is in, or the one named: `:region.remove Verse`. Its clips and the markers stay. |
| `dir` | Delete the clips in the region that the cursor is in, on this track. The region stays. |
| `dar` | Delete the clips in the region that the cursor is in, on every track. The region stays. |
| `<Space>rl`, `:region.loop Verse` | Loop the region that the cursor is in, or the one named. |
| `<Space>rR`, `:render.regions out` | Render each region to a file of its own: `01 Intro.wav`, and the next files. `<Space>rR` asks for the folder. |
| `<Space>fm` `<Space>fr` | Find a marker, a region, in a picker. |

A region is also a range for `:render`: `:render out.wav range=Verse`
(see [Render](render.md)).

## Graphical window

| Gesture | Effect |
| --- | --- |
| Right click on the timeline | Put a marker there, or make a region over the selection or the loop. |
| Click a marker | Go to it. |
| Drag a marker | Move it. |
| The menu of a marker or region | Rename or remove it. Loop a region. |

## Lua

| Function | Effect |
| --- | --- |
| `paw.markers.add(16, "Chorus")` | Add a marker at beat 16. |
| `paw.markers.add(0, "Intro", { length = 16 })` | Add a region of 16 beats. |
| `paw.markers.list()` | All markers and regions. |
| `paw.markers.find("Chorus")` | A marker by name. |
| `paw.markers.set(id, { beat = 24 })` | Change a marker. |
| `paw.markers.remove(id)` | Remove a marker. |
| `paw.markers.render_regions(dir, opts)` | Render each region. |
