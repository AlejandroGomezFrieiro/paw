# The track column and the bar labels

<!-- tags: trackcolumn statuscolumn paw.trackcolumn paw.ruler number relativenumber relativebar -->

The track column is at the left of the track headers of the arrange view,
and the bar labels are on its ruler. Each is a list of parts, and an extension
can add its own parts. The arrange view draws them in cells, so the terminal
and the graphical window show the same column and ruler. For what the
user sees, see [The arrange view](arrange-view.md#the-track-column).

## The parts of the track column

| Part | Order | Shows |
| --- | --- | --- |
| `number` | 10 | The number of the track, or with `relativenumber` how many `j` or `k` go to it. |
| `signs` | 20 | One sign for each track: the sign of the highest priority. No column when no track has one. |
| `fold` | 30 | The groups as a tree: `▾` `▸` on a group, `│` and `╰` down its members. A click on `▾` or `▸` folds or opens the group. |

The parts show from the left by their order, and `paw.opt.trackcolumn` names
the parts that show, so `:set trackcolumn=number,fold` removes the signs.
Without `fold`, the header puts the mark of a group before its name and
indents its members a step.

## paw.trackcolumn.add

```lua
paw.trackcolumn.add("rec", {
  order = 25,
  width = 1,
  render = function(track, ctx)
    if ctx.line == 0 and ctx.kind == "track" and paw.track(track).armed then
      return { { "●", "TrackSign" } }
    end
  end,
})
```

`add` puts the name of the part in `paw.opt.trackcolumn`, so the part
shows at once, and `hidden = true` adds it without doing so. A part with a name
that exists replaces the old part, and `paw.trackcolumn.remove("rec")` removes it.

| Field | Meaning |
| --- | --- |
| `order` | The place among the other parts. A lower order is more to the left. The default is 50. |
| `width` | The columns of the part. A function `width(frame)` gives them for each draw. 0 hides the part. |
| `render(track, ctx)` | What the part shows on one line of a track: nothing, a text, or a list of `{ text, style }`. The arrange view calls it for each line of each track that shows. |
| `click(track, ctx)` | What a click on the part does. `ctx.x` is the column of the part that has the click. |
| `describe(track, ctx)` | A line that `K` adds about the track of the cursor, or nothing. |
| `glyphs` | The characters that the part draws, by name. |
| `styles` | The highlight groups that the part draws in, by name. |

`frame` has `rows`, the ids of the tracks that show, in order, and
`count`, how many lines the counts of `j` and `k` go over.

`ctx` has the fields below, which describe the line.

| Field | Meaning |
| --- | --- |
| `row` | The number of the track: its place among the tracks that show, the number that `5G` takes. |
| `line` | 0 on the first line of the row of the track, then 1, 2 on the lines under it. |
| `kind` | `track`, `lane` (an automation lane that shows as a row) or `take` (a take lane). |
| `lane` | The id of the lane on a `lane` row. |
| `relative` | How many `j` or `k` go to the line. Nil on a line that the counts do not stop on. |
| `cursor` | True on the line of the cursor. |
| `width` | The columns of the part. |
| `g` | The glyphs of paw (`paw.draw.g`), plain ASCII with `paw.opt.ascii`. |
| `glyphs`, `styles` | The glyphs and the styles of the part. |

A part that has an error shows `!`, and the other parts still show.

## paw.trackcolumn.set

`set` changes a part that exists, including a part that comes with paw, and it
changes only the fields that you give. The `glyphs` and `styles` that
you give go into those of the part, and the other glyphs and styles stay.

```lua
-- The folds at the far left, with plus and minus signs, in the dim color.
paw.trackcolumn.set("fold", { order = 5, glyphs = { open = "-", closed = "+", guide = "|", last = "`" }, styles = { fold = "Dim" } })
-- Four columns for the numbers, and the cursor's number in another color.
paw.trackcolumn.set("number", { width = 4, styles = { cursor = "Title" } })
-- Other characters for the signs of the diagnostics.
paw.trackcolumn.set_sign("diagnostics", { glyphs = { error = "E", warn = "W" } })
```

To change the order, give a new `order`, and to replace a part, add a part
with its name. To remove one, use `paw.trackcolumn.remove` or take its
name out of `paw.opt.trackcolumn`.

`set` does not change the table of the part, and instead puts a changed copy in
`paw.trackcolumn.components` and returns it. To put a part back as it
was, keep its table before you change it and add it again, as follows.

```lua
local fold = paw.trackcolumn.components.fold
paw.trackcolumn.set("fold", { glyphs = { open = "-" } })
paw.trackcolumn.add("fold", fold)   -- the folds of paw again
```

paw records each part, sign and change that an extension makes, and when
the extension unloads, paw removes its parts and signs and puts back
each part that it changed. The field `ext` of a part names the
extension that added it or changed it last.

| Part | Glyphs | Styles |
| --- | --- | --- |
| `number` | | `number`, `relative`, `cursor` |
| `signs` | | `sign` (for a sign that gives no style) |
| `fold` | `open`, `closed`, `guide`, `last` | `fold` |
| the sign `diagnostics` | `error`, `warn` | `error`, `warn` |

`K` on a track adds what the parts say, where `fold` gives the group of the
track and, on a group, how many tracks it holds, and `signs` gives what each
sign says, for example the count of the diagnostics.

## paw.trackcolumn.sign

```lua
paw.trackcolumn.sign("todo", {
  priority = 5,
  render = function(track)
    if paw.track(track).name:find("TODO") then return { { "?", "TrackSign" } } end
  end,
})
```

A sign is one character in the `signs` part. When two signs have a
character for a track, the sign with the higher `priority` shows, and the
diagnostics of language servers have priority 30.
`paw.trackcolumn.sign("todo", nil)` removes the sign.

## paw.ruler.add

```lua
paw.ruler.add("odd", {
  order = 20,
  render = function(bar, ctx)
    if bar % 2 == 1 then return { { "'", "RulerTick" } } end
  end,
})
```

The label of each bar on the ruler is a list of parts. The part `number`
(order 10) shows the number of the bar, or with `relativebar` how many `W`
or `B` go to it, and a part shows after the parts of a lower order.
`paw.opt.barlabel` names the parts that show, and `add` puts the name in
it. `paw.ruler.remove("odd")` removes the part.

`paw.ruler.set(name, patch)` changes a part that exists: its `order`,
its `render`, its `glyphs` and its `styles`. Like `paw.trackcolumn.set`,
it puts a changed copy in `paw.ruler.labels`. The part `number` has the
styles `cursor` and `relative`.

```lua
paw.ruler.set("number", { styles = { cursor = "Title", relative = "Dim" } })
```

## paw.ruler.add_lane

```lua
paw.ruler.add_lane("cues", {
  order = 20,
  rows = function(ctx) return 1 end,
  render = function(ctx) ctx.buf:text(ctx.x(16), 0, "cue", "Marker") end,
})
```

Under the bar numbers, the ruler has lanes of rows. The lane `regions`
(order 10) shows the regions, a row for each level (see
[Markers and regions](markers.md)). A lane shows after the lanes of a lower
order.

`rows` gives the number of rows that the lane needs now, 0 for
none. `render` draws them on `ctx.buf`. `ctx.x(beat)` is the column of a
beat. `paw.ruler.remove_lane(name)` removes the lane.

`paw.ruler.set_lane(name, patch)` changes a lane that exists: its
`order`, `rows`, `render`, `glyphs` and `styles`. It puts a changed copy
in `paw.ruler.lanes`.

A bar label has no `click` and no `describe`, because a click on the ruler moves
the playhead and `K` describes the track and the clip at the cursor.

| Field of `ctx` | Meaning |
| --- | --- |
| `bar` | The number of the bar. |
| `beat` | Where the bar starts. |
| `relative` | How many `W` or `B` go to the bar. Nil when `relativebar` is off. |
| `cursor` | True on the bar of the cursor. |
| `style` | The style of the bar number there: in the loop, in the punch range. |
| `room` | The columns that the parts before this part left, up to the next label. A part that needs more columns shows less, or nothing. |
| `g` | The glyphs. |

## Examples

[How to personalize the track column and the
ruler](../how-to/personalize-the-track-column-and-the-ruler.md) gives
the steps. Two bundled extensions use the whole API,
[columnplus](../../extensions/columnplus/README.md) for the track column
and [rulerplus](../../extensions/rulerplus/README.md) for the bar labels.

## Highlight groups

| Group | What |
| --- | --- |
| `TrackColumn`, `TrackColumnCursor` | The ground of the column, and of the line of the cursor. |
| `TrackNr`, `TrackNrCursor` | The numbers, and the number of the cursor's track. |
| `TrackFold` | The marks and lines of the groups. |
| `TrackSign` | A sign that gives no style. |
| `RulerBarCursor`, `RulerBarRelative` | With `relativebar`: the bar of the cursor, and the counts of the other bars. |
