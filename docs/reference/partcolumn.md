# The part column

<!-- tags: partcolumn statuscolumn paw.partcolumn number relativenumber -->

The part column is at the left of the part headers of the arrange view.
It is a list of components, and an extension can add its own components.
The arrange view draws them in cells, so the terminal and the graphical
window show the same column. For what the user sees, see [The arrange
view](arrange-view.md#the-part-column). The ruler above the parts has its
own page, [The ruler](ruler.md).

## The components of the part column

| Part | Order | Shows |
| --- | --- | --- |
| `number` | 10 | The number of the part, or with `relativenumber` how many `j` or `k` go to it. |
| `signs` | 20 | One sign for each part: the sign of the highest priority. No column when no part has one. |
| `fold` | 30 | The groups as a tree: `▾` `▸` on a group, `│` and `╰` down its members. A click on `▾` or `▸` folds or opens the group. |

The components show from the left by their order, and `paw.opt.partcolumn` names
the components that show, so `:set partcolumn=number,fold` removes the signs.
Without `fold`, the header puts the mark of a group before its name and
indents its members a step.

## paw.partcolumn.add

```lua
paw.partcolumn.add("rec", {
  order = 25,
  width = 1,
  render = function(part, ctx)
    if ctx.line == 0 and ctx.kind == "part" and paw.part(part).armed then
      return { { "●", "PartSign" } }
    end
  end,
})
```

`add` puts the name of the component in `paw.opt.partcolumn`, so the component
shows at once, and `hidden = true` adds it without doing so. A component with a name
that exists replaces the old component, and `paw.partcolumn.remove("rec")` removes it.

| Field | Meaning |
| --- | --- |
| `order` | The place among the other components. A lower order is more to the left. The default is 50. |
| `width` | The columns of the component. A function `width(frame)` gives them for each draw. 0 hides the component. |
| `render(part, ctx)` | What the component shows on one line of a part: nothing, a text, or a list of `{ text, style }`. The arrange view calls it for each line of each part that shows. |
| `click(part, ctx)` | What a click on the component does. `ctx.x` is the column of the component that has the click. |
| `describe(part, ctx)` | A line that `K` adds about the part of the cursor, or nothing. |
| `glyphs` | The characters that the component draws, by name. |
| `styles` | The highlight groups that the component draws in, by name. |
| `from_header` | When `true`, the component takes its columns from the part headers and not from the timeline, so the timeline stays in place when the component shows or hides. `signs` and `fold` have it. In a narrow window, where the headers have no columns to give, the component takes them from the timeline. |

`frame` has `rows`, the ids of the parts that show, in order, and
`count`, how many lines the counts of `j` and `k` go over.

`ctx` has the fields below, which describe the line.

| Field | Meaning |
| --- | --- |
| `row` | The number of the part: its place among the parts that show, the number that `5G` takes. |
| `line` | 0 on the first line of the row of the part, then 1, 2 on the lines under it. |
| `kind` | `part`, `lane` (an automation lane that shows as a row) or `take` (a take lane). |
| `lane` | The id of the lane on a `lane` row. |
| `relative` | How many `j` or `k` go to the line. Nil on a line that the counts do not stop on. |
| `cursor` | True on the line of the cursor. |
| `width` | The columns of the component. |
| `g` | The glyphs of paw (`paw.draw.g`), plain ASCII with `paw.opt.ascii`. |
| `glyphs`, `styles` | The glyphs and the styles of the component. |

A component that has an error shows `!`, and the other components still show.

## paw.partcolumn.set

`set` changes a component that exists, including a component that comes with paw, and it
changes only the fields that you give. The `glyphs` and `styles` that
you give go into those of the component, and the other glyphs and styles stay.

```lua
-- The folds at the far left, with plus and minus signs, in the dim color.
paw.partcolumn.set("fold", { order = 5, glyphs = { open = "-", closed = "+", guide = "|", last = "`" }, styles = { fold = "Dim" } })
-- Four columns for the numbers, and the cursor's number in another color.
paw.partcolumn.set("number", { width = 4, styles = { cursor = "Title" } })
-- Other characters for the signs of the diagnostics.
paw.partcolumn.set_sign("diagnostics", { glyphs = { error = "E", warn = "W" } })
```

To change the order, give a new `order`, and to replace a component, add a component
with its name. To remove one, use `paw.partcolumn.remove` or take its
name out of `paw.opt.partcolumn`.

`set` does not change the table of the component, and instead puts a changed copy in
`paw.partcolumn.components`, a registry, and returns it. To put a component back as it
was, keep its table before you change it and add it again, as follows.

```lua
local fold = paw.partcolumn.components:get("fold")
paw.partcolumn.set("fold", { glyphs = { open = "-" } })
paw.partcolumn.add("fold", fold)   -- the folds of paw again
```

paw records each component, sign and change that an extension makes, and when
the extension unloads, paw removes its components and signs and puts back
each component that it changed. The field `ext` of a component names the
extension that added it or changed it last.

| Part | Glyphs | Styles |
| --- | --- | --- |
| `number` | | `number`, `relative`, `cursor` |
| `signs` | | `sign` (for a sign that gives no style) |
| `fold` | `open`, `closed`, `guide`, `last` | `fold` |
| the sign `diagnostics` | `error`, `warn` | `error`, `warn` |

`K` on a part adds what the components say, where `fold` gives the group of the
part and, on a group, how many parts it holds, and `signs` gives what each
sign says, for example the count of the diagnostics.

## paw.partcolumn.sign

```lua
paw.partcolumn.sign("todo", {
  priority = 5,
  render = function(part)
    if paw.part(part).name:find("TODO") then return { { "?", "PartSign" } } end
  end,
})
```

A sign is one character in the `signs` component. When two signs have a
character for a part, the sign with the higher `priority` shows, and the
diagnostics of language servers have priority 30.
`paw.partcolumn.sign("todo", nil)` removes the sign.

## Examples

[How to personalize the part column and the
ruler](../how-to/personalize-the-part-column-and-the-ruler.md) gives
the steps. The bundled extension
[columnplus](../../extensions/columnplus/README.md) uses the whole API.

## Highlight groups

| Group | What |
| --- | --- |
| `PartColumn`, `PartColumnCursor` | The ground of the column, and of the line of the cursor. |
| `PartNr`, `PartNrCursor` | The numbers, and the number of the cursor's part. |
| `PartFold` | The marks and lines of the groups. |
| `PartSign` | A sign that gives no style. |
