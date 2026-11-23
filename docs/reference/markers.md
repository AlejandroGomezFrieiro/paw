# Markers and regions

<!-- tags: markers regions -->

A marker is a named place in the song. A region is a named time range.
They are in the lane of regions, under the bar numbers of the ruler. The
graphical window shows the same rows. They move with the beats when the
tempo changes, and the project saves them. The module is `paw.markers`.

## Regions inside regions

A region inside the time of another region is its child. For example,
`Chorus 2` from bar 5 to bar 12 holds `Verse A` (bars 5 to 8) and
`Verse B` (bars 9 to 12). paw saves no link: the times make the tree, and
the project files do not change.

- The parent of a region is the smallest region that holds its time.
- Of two regions with the same time, the region made first holds the other.
- Two regions that overlap and do not nest are siblings. Where both are,
  `ar` takes the one that starts later.
- A marker belongs to the innermost region around it.
- Regions with no region inside them are a tree of one level. They work
  as before.

## The lane of regions

The lane of regions has a row for each level of regions. A region is on
the row under the region around it, as a track is under its group. The
markers are on the first row.

- `paw.opt.regionlevels` (default 3) sets the number of rows. A deeper
  region is on the last row, with `+` before its name.
- `▾` comes before the name of a region with regions inside it. `▏` comes
  before the name of a region with no region inside it. `▼` comes before
  the name of a marker.
- `▸` comes before the name of a region that is folded into one column
  (see [Time folds](narrowing.md#time-folds)). The regions and markers
  inside it do not show.
- The styles are `RulerRegion1` (the top level), `RulerRegion2` (the
  second level), `RulerRegionDeep` (the third level and deeper) and
  `Marker`.
- A click on a row takes the region of that row.

The lane is the part `regions` of `paw.ruler` (see
[The track column and the bar labels](trackcolumn.md#pawruleradd_lane)).
An extension changes its glyphs and styles:

```lua
paw.ruler.set_lane("regions", { styles = { level1 = "Title" }, glyphs = { open = "-", closed = "+" } })
```

## Key changes

A marker named `key D minor` is a key change, and the harmony reading uses it from its beat (see [Harmony](harmony.md)). The pencil's `mk` writes one, and so does `:key D minor at 17`, at bar 17. A region can have a `key` field, as in `paw.markers.add(32, "Verse", { length = 16, key = "E minor" })`, and `paw.markers.set(id, { key = "A minor" })` changes it. The region's key holds over its time.

## Keys and commands

| Keys, command | Effect |
| --- | --- |
| `g'` `<Space>rm`, `:marker Chorus` | Put a marker at the cursor. `g'` and `<Space>rm` ask for its name. A marker with no name typed is `Marker 1`, `Marker 2` and so on. |
| `<Space>rn`, `:region Verse` | Make a region over the selection, or over the loop. `<Space>rn` asks for its name. |
| `]'` `['` | Go to the next start of a marker or region, or the one before. You can use them as motions, e.g., `d]'`. |
| `]r` `[r`, `:region.next` `:region.prev` | Go to the next region at the level of the innermost region at the cursor, or to the one before. At the top level when the cursor is in no region. These are motions. |
| `g"`, `:marker.list` | List all markers and regions. Select one to go there. A region inside another region is indented under it. |
| `:marker.goto 3`, `:marker.goto Chorus` | Go to a marker by number or by name. |
| `:marker.rename Bridge` | Rename the marker at the cursor. |
| `:marker.move` | Move the nearest marker or region start to the cursor. A region takes the regions and markers inside it. |
| `:region.move Chorus 2 +8` | Move a region 8 bars later (`-2`: 2 bars earlier) with the regions and markers inside it, in one undo step. With no bars, move it to the cursor. With no name, move the region that the cursor is in. |
| `:region.move! Chorus 2 +8` | Move the region alone. |
| `gx` `<Space>rx`, `:marker.remove` | Remove the marker at the cursor, or the one named: `:marker.remove Chorus`. Regions stay. |
| `gX` `<Space>rX`, `:region.remove` | Remove the region that the cursor is in, or the one named: `:region.remove Verse`. Its clips and the markers stay. The regions inside it move up one level. |
| `:region.remove! Chorus 2` | Remove the region and the regions inside it. The clips and the markers stay. |
| `dir` | Delete the clips in the innermost region that the cursor is in, on this track. The region stays. |
| `dar` | Delete the clips in the innermost region that the cursor is in, on every track. The region stays. |
| `d2ar` | Delete the clips in the region around that region (its parent). `3ar` is the next level out. |
| `<Space>rl`, `:region.loop Verse` | Set the playback loop to the region that the cursor is in, or to the one named, and turn looping on. |
| `:render.regions out` | Render each region to a file of its own: `01 Intro.wav`, and the next files. A region inside another region has the path in its name: `02 Chorus 2 - 01 Verse A.wav`. Each number is the place among the regions with the same parent. `level=1` renders only the top level, `level=2` only the second level, and `level=leaves` the regions with no region inside. With no folder, it asks for the folder. `<Space>er` exports the regions with `:export regions` (see [Render](render.md#export)). |
| `<Space>fm` `<Space>fr` | Find a marker, a region, in a picker. The region picker shows the regions as a tree, and its preview shows the path. |

A region is also a range for `:render`: `:render out.wav range=Verse`
(see [Render](render.md)). When two regions have the same name, give the
path: `range=Chorus 2/Verse A`.

## Graphical window

| Gesture | Effect |
| --- | --- |
| Right click on the timeline | Put a marker there, or make a region over the selection or the loop. |
| Click a marker | Go to it. |
| Drag a marker | Move it. A region takes the regions and markers inside it. |
| The menu of a marker or region | Rename or remove it. Loop a region. |

## Lua

| Function | Effect |
| --- | --- |
| `paw.markers.add(16, "Chorus")` | Add a marker at beat 16. |
| `paw.markers.add(0, "Intro", { length = 16 })` | Add a region of 16 beats. |
| `paw.markers.list()` | All markers and regions. |
| `paw.markers.find("Chorus")` | A marker by name. |
| `paw.markers.set(id, { beat = 24 })` | Change a marker. |
| `paw.markers.remove(id)` | Remove a marker. `paw.markers.remove(id, true)` also removes the regions inside a region. |
| `paw.markers.move(id, beat)` | Move a marker or a region, with the regions and markers inside it. `paw.markers.move(id, beat, true)` moves it alone. |
| `paw.markers.tree()` | The regions at the top level, each a node with `region`, `depth`, `place`, `parent` and `children`. |
| `paw.markers.walk()` | Each node, in the order of the tree. |
| `paw.markers.parent(id)`, `paw.markers.children(id)`, `paw.markers.depth(id)` | The region around a region or marker, the regions one level inside it, its level (1 at the top). |
| `paw.markers.path(beat)` | The regions around a beat, the outermost first. |
| `paw.markers.pathname(region)` | The names from the top: `Chorus 2/Verse A`. |
| `paw.markers.region("Chorus 2/Verse A")` | A region by name, number or path. |
| `paw.markers.render_regions(dir, opts)` | Render each region. |
