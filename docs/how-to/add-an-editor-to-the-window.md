# How to give an extension an editor in the graphical window

You can give an extension an editor that draws in pixels, and you can open
the editor from the menus of the graphical window. The steps assume that
you already have an extension (see
[How to load an extension](load-an-extension.md)). The window itself needs
no code for it.

## Write the view

1. In the extension, define a view with a `paint` function. The function
   gets a painter `g` and the size of the area in `ctx`:

   ```lua
   paw.ui.view("scope", {
     paint = function(self, g, ctx)
       local c = paw.canvas.palette
       g:rect(0, 0, ctx.width, ctx.height, { fill = c.surface })
       g:text(12, 10, "hello", { color = c.text, size = 14, bold = true })
     end,
     pointer = function(self, e)
       if e.kind == "down" then paw.notify(("click at %d, %d"):format(e.x, e.y)) end
     end,
   })
   ```

2. Use the colors of `paw.canvas.palette`, so that the view looks like the
   rest of the window.
3. If you want the view to have keys, map them for the view in the same
   way as in the terminal.

## Give it a place

1. To show the view in a pane, say where it docks:

   ```lua
   paw.ui.dock("scope", { side = "bottom", hidden = true })
   ```

2. Open it with `paw.canvas.open`:

   ```lua
   paw.canvas.open("scope", { title = "Scope", width = 640, height = 360 })
   ```

   If the view does not dock, it opens in a window of its own with that
   size. `window = true` also opens it in a window of its own.

## Open it from a menu

1. Make a command that opens the view, for example `:scope.open`.
2. Add an entry to the menu of a clip, a track or the timeline:

   ```lua
   table.insert(paw.frontend.menus.clip, { label = "Open in the scope", command = "scope.open", only = "audio" })
   ```

3. If the editor is for the clips of a kind of track, give the kind an
   `editor`, and a double-click on such a clip opens it. For other clips,
   add a function to `paw.frontend.openers`.

## Show it in the terminal too

If the terminal can show images, keep cells for the pixels in the view's
`render` with `buf:surface(x, y, w, h)`. When you do, `ctx.surface` is
true in `paint`, and `ctx.cell` gives the size of a cell. If the terminal
shows only text cells, `render` draws them.

## Related

- [The graphical window in Lua](../reference/window-lua.md): the painter, `ctx`, the pointer events, menus and bands.
- [About scenes](../explanation/about-scenes.md): why one view works in the two frontends.
