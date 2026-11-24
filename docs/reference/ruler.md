# The ruler

<!-- tags: ruler paw.ruler paw.marks rulerrows relativebar marks namespaces -->

The ruler is at the top of the arrange view, over the parts. It has rows,
and each row shows marks: the numbers of the bars, the changes of tempo
and meter, the markers and the regions, the loop, and the marks of
extensions. One function places every mark of every row, so a mark is
always in the column of its time, at each zoom level, in the terminal and
in the graphical window. For what the user sees, see [The arrange
view](arrange-view.md).

The design follows Neovim. A row is like a part of the `statuscolumn`, and
a mark is like an `extmark`: it belongs to a namespace, and it has a sign, a
label and a priority.

## The rows of paw

| Row | Lines | Shows |
| --- | --- | --- |
| `bars` | 1, or 2 in a subproject | The number of each bar, or with `relativebar` how many `W` or `B` go to it. In a subproject, a second line gives the song's bar (`@9`). |
| `beats` | none, it draws on `bars` | A tick on each beat, from two columns a beat. |
| `regions` | one for each level of regions | The regions and the markers (see [Markers and regions](markers.md)). |
| `tempo` | 2 while the tempo lane shows | The tempo lane. |

`paw.opt.rulerrows` names the rows that show, from the top. The default is
`bars,beats,regions,tempo`, and `:set rulerrows-=regions` hides the
regions. An extension that adds a row puts its name in the option.

## The namespaces of paw

| Namespace | Goes to | Priority | Marks |
| --- | --- | --- | --- |
| `paw.meter` | over `bars` | 50 | `‖` and the time signature at each change. |
| `paw.tempo` | over `bars` | 40 | `▾` and the tempo at each change. |
| `paw.cues` | a line of `regions` | 30 | `▼` and the name of each marker. |
| `paw.regions` | the lines of `regions` | 20 | Each region: its color over its time, and a sign and its name at its start. |
| `paw.loop` | over `bars` | 20 | The loop: a color over its time, and a sign at each edge. |
| `paw.punch` | over `bars` | 20 | The punch range, as the loop. |
| `paw.selection` | over `bars` | 20 | The time selection of visual mode. |

The bar numbers have priority 10 and the ticks of the beats priority 1.

## How the marks are placed

A mark at a time has a sign, a label, or both. A mark over a stretch of
time (`to`) colors the background of its stretch.

- A sign is one cell in the column of its time. An `edge` sign is in the
  cell before that column, as the edges of the loop are.
- In one line of a row, a column shows one sign: the sign of the highest
  priority.
- The labels of a column follow its sign in the order of their priority,
  with a space between them. A mark whose sign does not win the column
  shows its sign before its label.
- A label never covers a sign of another column, unless the sign is
  `soft` and has a lower priority. The ticks of the beats and the edges of
  the loop and the punch range are soft, so a tempo or a time signature
  covers an edge, and the color of the stretch still shows where it ends.
- A label keeps a free cell before the next label. It can end in the cell
  just before a sign.
- The labels with a higher priority get their room first. A `whole` label,
  such as a bar number or a tempo, shows whole or not at all. Another
  label, such as a name, gets shorter with `…`.
- A label stops at a time fold and at the end of a scope.
- Over a stretch, the color of the highest priority wins, and the text in
  it can take another style there (`restyle`), as the bar numbers in the
  loop do.

`K` with the cursor between clips lists each mark of the ruler in the
column of the cursor, on each row, and it says what has no room to show:

```
Ruler  column 40
  bars     ▾ tempo 100  (no room for 100)
  regions  ▏ region Hit
```

## paw.ruler.row

```lua
paw.ruler.row("odd", {
  after = "bars",
  marks = function(ctx)
    local out = {}
    for _, line in ipairs(paw.draw.grid_lines(ctx.axis, ctx.right)) do
      if line.bar and line.bar % 2 == 1 then
        out[#out + 1] = { beat = line.beat, label = "odd", style = "RulerTick" }
      end
    end
    return out
  end,
})
```

`row` adds a row, or replaces the row of that name. Its name goes into
`paw.opt.rulerrows` after the row `after`, or at the end.
`paw.ruler.remove(name)` removes the row and takes its name out of the
option.

| Field | Meaning |
| --- | --- |
| `marks(ctx)` | The marks of the row for the time in sight, as a list. |
| `height(ctx)` | How many lines the row takes now. The default is 1, and 0 hides the row. |
| `draw(ctx)` | Draws the lines of the row on `ctx.buf`, and on `ctx.header` over the part headers, as the tempo lane does. |
| `over` | The name of a row to draw on. The row then has no lines of its own, as `beats` draws on `bars`. |
| `priority` | The priority of a mark that gives none. The default is 10. |
| `glyphs`, `styles` | The characters and the highlight groups of the row, by name. `ctx.glyphs` and `ctx.styles` give them to `marks`. |
| `after` | The row that the new row goes after in `paw.opt.rulerrows`. |
| `hidden` | When `true`, the name does not go into `paw.opt.rulerrows`. |

A row or a namespace that has an error shows the error on the first line
of the ruler, and the other rows still show.

## The fields of a mark

| Field | Meaning |
| --- | --- |
| `beat` | The time of the mark, in beats. |
| `to` | The end of a stretch of time. A mark with `to` colors its stretch. |
| `sign` | One character in the column of `beat`. |
| `label` | The text after the sign. |
| `whole` | When `true`, the label shows whole or not at all. |
| `priority` | Which sign a column shows, and which label gets its room first. |
| `style`, `label_style` | The highlight group of the mark, and of its label when it is different. |
| `edge` | When `true`, the sign is in the cell before the column of `beat`. |
| `soft` | When `true`, a label of a higher priority can cover the sign, as with the ticks of the beats and the edges of the loop. |
| `restyle` | For a stretch: the style that each style of the text over it takes. |
| `row`, `over` | The row that shows the mark, as the route of a namespace says. |
| `line` | The line of the row, from 0. |
| `text` | What `K` says of the mark. The default is the label. |
| `kind`, `ref` | What the mark marks, for example `"region"` and the id of the region. |
| `cmd` | A command that a click on the mark runs. |

## The context

`marks`, `height` and `draw` get `ctx` with the fields below. The beats
are the beats of the window: inside a subproject, they start at 0 at the
start of the subproject.

| Field | Meaning |
| --- | --- |
| `left`, `right` | The beats at the left and the right edge of the ruler. |
| `here(beat)` | The beat of the window for a beat of the song. |
| `from`, `to` | The time of the scope of the window, nil when it shows the whole song. |
| `axis` | The time axis of the window: `ctx.axis:x_of(beat)` is the column of a beat. |
| `folded(beat)` | True for a beat inside a closed time fold, after its start. |
| `closed(id)` | True for a region that is folded into its column (see [Time folds](narrowing.md#time-folds)). |
| `cursor` | The beat of the cursor. |
| `glyphs`, `styles` | The glyphs and the styles of the row or the namespace. |
| `buf`, `header` | For `draw` only: the lines of the row over the timeline and over the part headers. |

## paw.marks.namespace

```lua
local ns = paw.marks.namespace("todo", { route = "row:regions", priority = 25 })
```

A namespace holds marks of one owner. `namespace` makes it and gives its
id, or gives the id of the namespace of that name.

| Field | Meaning |
| --- | --- |
| `route` | Where its marks go: `"row:<row>"` gives them a line of that row, and `"over:<row>"` draws them on the lines that the row has. The default is `"over:bars"`. |
| `priority` | The priority of a mark that gives none. The default is 10. |
| `source(ctx)` | A function that gives marks for the time in sight, in the beats of the window, as the marks of a row. |
| `glyphs`, `styles` | The characters and the highlight groups of the namespace. |

A mark can give its own `row` or `over`, in place of the route of its
namespace.

## paw.marks.set, del, clear and get

```lua
local id = paw.marks.set(ns, 32, { sign = "?", label = "fix the fill", style = "Marker" })
paw.marks.del(ns, id)
paw.marks.clear(ns)          -- every mark of the namespace
paw.marks.clear(ns, 0, 64)   -- the marks from beat 0 up to beat 64
```

`set` puts a mark at a beat of the song in a namespace, by its id or its
name, and gives the id of the mark. With `id` in the table, it changes
that mark. The beats are the song's: in a subproject, the ruler shows
the mark at its place in the subproject, and not at all outside it.
`del` removes one mark, `clear` removes the marks of a stretch or all of
them, and `get` gives the marks of a namespace in the order of their
beats.

## paw.ruler.route

```lua
paw.ruler.route("paw.cues", "over:bars")   -- the markers over the bar numbers
paw.ruler.route("paw.cues", nil)           -- back to the regions
```

`route` sends the marks of a namespace to another row. Your route wins
over the route of the namespace.

## paw.ruler.set

```lua
paw.ruler.set("bars", { styles = { cursor = "Title" }, glyphs = { ahead = "+", behind = "-" } })
paw.ruler.set("paw.meter", { glyphs = { sign = "M" }, priority = 60 })
```

`set` changes a row or a namespace that exists, also those of paw: the
`priority` of its marks, and the `glyphs` and the `styles` that it draws
with. The glyphs and the styles that you do not give stay as they are.
`set` puts a changed copy in `paw.ruler.rows` or `paw.marks.namespaces`,
two registries. A row is found first, then a namespace.

| Row or namespace | Glyphs | Styles |
| --- | --- | --- |
| `bars` | `ahead`, `behind`: before the counts of `relativebar` | `bar`, `cursor`, `relative` |
| `beats` | `tick` | `tick` |
| `paw.meter`, `paw.tempo` | `sign` | `mark` |
| `paw.cues` | `sign` | `cue` |
| `paw.regions` | `open`, `closed`, `start`, `deeper` | `level1`, `level2`, `deep` |
| `paw.loop`, `paw.punch` | `start`, `end` | |
| `paw.selection` | | `selection` |

## Extensions

paw records each row, namespace and change that an extension makes.
When the extension unloads, paw removes its rows and their names in
`paw.opt.rulerrows`, removes its namespaces with their marks, and puts
back each row and namespace that it changed. The field `ext` names the
extension that added or changed it last.

[How to add a row to the ruler](../how-to/add-a-row-to-the-ruler.md) gives
the steps, and the bundled extension
[rulerplus](../../extensions/rulerplus/README.md) uses the whole API.

## Highlight groups

| Group | What |
| --- | --- |
| `RulerBar` | The bar numbers. |
| `RulerBarCursor`, `RulerBarRelative` | With `relativebar`: the bar of the cursor, and the counts of the other bars. |
| `RulerTick` | The ticks of the beats. |
| `RulerTempo` | The changes of tempo and meter. |
| `RulerRegion1`, `RulerRegion2`, `RulerRegionDeep` | The regions of the top level, the second level, and deeper. |
| `Marker` | The markers. |
| `RulerLoop`, `RulerLoopOff`, `RulerLoopEdge`, `RulerLoopEdgeIn`, `RulerLoopOffEdge` | The loop when it is on and off, and its edges. |
| `RulerPunch` | The punch range. |
