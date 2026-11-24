# How to add a row to the ruler

The steps below put your own marks on the ruler of the arrange
view, in a row of their own, and move the marks of paw to another
row. You need a file `~/.config/paw/init.lua`.

## Add a row

The example row shows the word `odd` at each odd bar, under the bar
numbers.

1. Open `~/.config/paw/init.lua`.
2. Add the row:

   ```lua
   paw.ruler.row("odd", {
     after = "bars",
     styles = { odd = "RulerTick" },
     marks = function(ctx)
       local out = {}
       for _, line in ipairs(paw.draw.grid_lines(ctx.axis, ctx.right)) do
         if line.bar and line.bar % 2 == 1 then
           out[#out + 1] = { beat = line.beat, label = "odd", style = ctx.styles.odd, text = "an odd bar" }
         end
       end
       return out
     end,
   })
   ```

3. Type `:reload` in paw. The row shows under the bar numbers.

paw puts each label in the column of its bar, and it gives a label less
room, or none, when the bar is narrow. To see what has no room, put the
cursor between clips in the column and press `K`. To give a label more room than the others, give it a higher
`priority`.

## Put marks in a namespace

A namespace holds marks that you put at beats of the song. The example
puts a mark at beat 32, on the row of the regions:

```lua
local ns = paw.marks.namespace("todo", { route = "row:regions", priority = 25 })
paw.marks.set(ns, 32, { sign = "?", label = "fix the fill", style = "Marker" })
```

To remove the mark, use `paw.marks.del(ns, id)` with the id that `set`
gave, or `paw.marks.clear(ns)` to remove all the marks of the namespace.

## Send marks to another row

To show the markers of paw over the bar numbers, and not on the row of
the regions, add this to your `init.lua`:

```lua
paw.ruler.route("paw.cues", "over:bars")
```

`"row:regions"` gives the marks a line of the row, and `"over:bars"` draws
them on the lines that the row already has. [The ruler](../reference/ruler.md)
lists the namespaces of paw.

## Hide or move a row

`paw.opt.rulerrows` names the rows that show, from the top:

- `:set rulerrows-=odd` hides your row.
- `:set rulerrows=bars,beats,odd,regions,tempo` puts it under the regions.

## See also

- [The ruler](../reference/ruler.md): each function, field, glyph and
  style.
- [rulerplus](../../extensions/rulerplus/README.md): an extension that adds
  a row and a namespace, to copy.
- [How to personalize the part column and the
  ruler](personalize-the-part-column-and-the-ruler.md).
