# How to personalize the track column and the ruler

You can change the track column and the bar labels in your `init.lua`. The
track column is at the left of the track headers. It shows the number of
each track, its signs and the folds of the groups. The bar labels are
the numbers of the bars on the ruler.

## Change a part of paw

1. Open `~/.config/paw/init.lua`.
2. Give the folds of the groups other characters, and put them at the far
   left:

   ```lua
   paw.trackcolumn.set("fold", { order = 5, glyphs = { open = "-", closed = "+" } })
   ```

3. Show the number of the cursor's track in the color of the titles:

   ```lua
   paw.trackcolumn.set("number", { styles = { cursor = "Title" } })
   ```

4. Type `:reload` in paw.

The glyphs and the styles that you do not give stay as they are. [The
track column and the bar labels](../reference/trackcolumn.md) lists the
glyphs and the styles of each part.

## Add a sign

A sign is one character in the column. The example sign is a red dot on
each track that is ready to record. Add it to your `init.lua`:

```lua
paw.trackcolumn.sign("armed", {
  priority = 20,
  render = function(track)
    if paw.track(track).armed then return { { "●", "Armed" } } end
  end,
  describe = function(track)
    if paw.track(track).armed then return "ready to record" end
  end,
})
```

When you press `K` on an armed track, the description says "ready to
record".

## Add a part to the bar labels

The example part puts a dot before the number of every eighth bar, from
bar 9:

```lua
paw.ruler.add("eight", {
  order = 5,
  render = function(bar)
    if bar > 1 and bar % 8 == 1 then return { { "·", "RulerTempo" } } end
  end,
})
```

A part with an `order` less than 10 shows before the number of the bar,
and a part with a higher `order` shows after it.

## Hide a part

To hide a part, take its name out of the option:

- `:set trackcolumn-=signs` hides the signs.
- `:set barlabel-=eight` hides the dots.

## Make it an extension

If you want to load and unload your changes as one, put them in a file in
`~/.config/paw/extensions`, for example `mycolumn.lua`, in place of
`init.lua`. Then `:ext.unload mycolumn` removes your parts and signs, and
it puts back the parts of paw that you changed. The bundled extensions
below are fuller examples to copy:

- [columnplus](../../extensions/columnplus/README.md): a color strip, clip
  counts, signs for takes and frozen tracks, other fold glyphs, keys and
  options.
- [rulerplus](../../extensions/rulerplus/README.md): phrase marks, the
  chord and the key where they change, and signed relative bars.

## See also

- [The track column and the bar labels](../reference/trackcolumn.md):
  each function, field, glyph and style.
- [How to write an extension in Teal](write-an-extension-in-teal.md).
