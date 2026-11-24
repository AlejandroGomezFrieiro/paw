# How to personalize the part column and the ruler

You can change the part column and the ruler in your `init.lua`. The
part column is at the left of the part headers. It shows the number of
each part, its signs and the folds of the groups. The ruler is over the
parts, and it shows the numbers of the bars and the marks of the song.

## Change a part of paw

1. Open `~/.config/paw/init.lua`.
2. Give the folds of the groups other characters, and put them at the far
   left:

   ```lua
   paw.partcolumn.set("fold", { order = 5, glyphs = { open = "-", closed = "+" } })
   ```

3. Show the number of the cursor's part in the color of the titles:

   ```lua
   paw.partcolumn.set("number", { styles = { cursor = "Title" } })
   ```

4. Type `:reload` in paw.

The glyphs and the styles that you do not give stay as they are. [The
part column](../reference/partcolumn.md) lists the glyphs and the styles
of each part. The ruler changes the same way:

```lua
paw.ruler.set("bars", { styles = { cursor = "Title" } })
```

[The ruler](../reference/ruler.md) lists the glyphs and the styles of
its rows and marks.

## Add a sign

A sign is one character in the column. The example sign is a red dot on
each part that is ready to record. Add it to your `init.lua`:

```lua
paw.partcolumn.sign("armed", {
  priority = 20,
  render = function(part)
    if paw.part(part).armed then return { { "●", "Armed" } } end
  end,
  describe = function(part)
    if paw.part(part).armed then return "ready to record" end
  end,
})
```

When you press `K` on an armed part, the description says "ready to
record".

## Add a mark to the ruler

The example puts a dot before the number of every eighth bar, from bar 9:

```lua
paw.marks.namespace("eight", {
  source = function(ctx)
    local out = {}
    for _, line in ipairs(paw.draw.grid_lines(ctx.axis, ctx.right)) do
      if line.bar and line.bar > 1 and line.bar % 8 == 1 then
        out[#out + 1] = { beat = line.beat, sign = "·", style = "RulerTempo", text = "eight bars" }
      end
    end
    return out
  end,
})
```

The marks of a namespace go over the bar numbers, unless you give the
namespace another `route`. [How to add a row to the
ruler](add-a-row-to-the-ruler.md) gives more.

## Hide a part

To hide a part, take its name out of the option:

- `:set partcolumn-=signs` hides the signs.
- `:set rulerrows-=regions` hides the regions on the ruler.

## Make it an extension

If you want to load and unload your changes as one, put them in a file in
`~/.config/paw/extensions`, for example `mycolumn.lua`, in place of
`init.lua`. Then `:ext.unload mycolumn` removes your parts and signs, and
it puts back the parts of paw that you changed. The bundled extensions
below are fuller examples to copy:

- [columnplus](../../extensions/columnplus/README.md): a color strip, clip
  counts, signs for takes and frozen parts, other fold glyphs, keys and
  options.
- [rulerplus](../../extensions/rulerplus/README.md): phrase marks, the
  chord and the key where they change, and signed relative bars.

## See also

- [The part column](../reference/partcolumn.md) and [the
  ruler](../reference/ruler.md): each function, field, glyph and style.
- [How to write an extension in Teal](write-an-extension-in-teal.md).
