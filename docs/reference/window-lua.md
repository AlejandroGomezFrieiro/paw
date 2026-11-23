# The graphical window in Lua

The reference page describes the Lua tables and functions of the kernel that the
graphical window uses, and that extensions use to add to it. The window
itself is described in [The graphical window](window.md). Each function
also has an entry in the [Lua API reference](api.md).

## `paw.frontend.act`

`paw.frontend.act` holds what each gesture of a frontend means. The window
calls these functions in the kernel, they snap beats to the grid, and the
suite tests each one, so another frontend gets the same behavior when it
sends the same gestures.

The functions include the following.

- clips: `select_clip`, `select_clips_box`, `drag_clips`, `trim_clips`, `set_fade`, `set_clip_gain`, `split_clips`, `glue_clips`, `open_clip`
- parts: `move_part`, `set_part_height`, `sweep_flag`
- time: `select_range`, `set_loop`, `set_loop_edge`, `ruler_click`
- notes: `add_note`, `drag_notes`, `stretch_notes`, `select_notes_box`, `erase_notes`, `draw_velocities`, `quantize_notes`, `set_velocity`
- other: `set_param`, `float_pointer`, `drop`, `leave`, and the full list is the record `Act` in `runtime/lua/paw/frontend/core.tl`.

| Function | Effect |
| --- | --- |
| `paw.frontend.act.leave(how, then)` | Asks about changes that are not saved, then does `then`, for example `"open:" .. path`. |
| `paw.frontend.act.drop(paths, row, beat)` | Puts dropped files in the project. With a `row` (a position in the list of parts) and a `beat`, it puts the files one after the other on that part, at the beat on the grid. Without them, as a drop on the window. |
| `paw.frontend.chosen_clips()` | The clips selected with the pointer. The state marks each of these clips `selected`. |
| `paw.frontend.layout_get()` | The layout that the window keeps (see [What the window keeps](window.md#what-the-window-keeps)). An empty table when there is none. |
| `paw.frontend.layout_set(layout)` | Writes the layout to `window.json` in the kernel's state directory. |
| `paw.frontend.menu(kind, args)` | The entries of menu `kind` of the kernel, as data for the window to show. `paw.frontend.menu("shown")` is the menu that a view opened (a right-click in a pane drawn from its scene). |
| `paw.frontend.act.menu_choose(kind, args, path)` | Does the entry at `path` (its position from 1 in each menu down to it) of menu `kind`. |
| `paw.frontend.act.menu_dismiss()` | Closes the menu that a view opened, without a selection. |
| `paw.frontend.refresh()` | Makes the frontends get the state again, when nothing in the project changed. An extension calls it after a change of its own. |

The menus of the window are in `runtime/lua/paw/window_menus.tl`, beside
the mouse menus of the terminal.

## `paw.frontend.menus`

`paw.frontend.menus` holds the entries that extensions add to the
right-click menus of the window, in the three lists below.

| List | Menu |
| --- | --- |
| `clip` | The menu of a clip. |
| `part` | The menu of a part header. |
| `timeline` | The menu of the empty timeline. The buttons that make a part also offer these entries. |

Each entry is a table:

| Field | Value |
| --- | --- |
| `label` | The text of the entry. |
| `command` | A command line. |
| `run` | A function, given the clip or the part, and the beat clicked. |
| `only` | `"midi"` or `"audio"`: the entry of a clip is gray on other clips. |

Before `command` or `run`, the cursor moves to the clicked position.

```lua
table.insert(paw.frontend.menus.clip, { label = "Open as notation", command = "notation.open", only = "midi" })
table.insert(paw.frontend.menus.timeline, { label = "New drum part", run = function(part, beat) end })
```

## `paw.frontend.bands`

`paw.frontend.bands` is a registry of functions by name, and each function
returns the entries of a band under the markers of the arrange view's ruler,
which is a row in the terminal and in the window. The bands go in the order
of their names.

| Field | Value |
| --- | --- |
| `beat` | Where the entry starts. |
| `length` | Its length in beats. An entry without a length is a flag. |
| `name` | Its text. |
| `color` | `#rrggbb`. Without it, the color of the ruler's bars. |
| `command` | A command line for a click. |
| `run` | A function for a click, given the entry. |
| `hint` | What the status line shows over the entry. |

A band with no entries takes no space, and the arrange view calls the
functions each time that it draws. The findings of the mix are a band.

```lua
paw.frontend.bands:put("sections", function()
  return { { beat = 0, length = 16, name = "Intro", command = "section.goto 1", hint = "click goes there" } }
end)
```

## `paw.frontend.openers`

`paw.frontend.openers` is a list of functions, and a double-click on a clip
calls each one with the clip, before the piano roll opens. A function that
opens the clip in an editor of its own returns true. A kind of part with
an `editor` (see [Everything an extension can
own](extensions.md#what-the-core-gives-an-extension)) does not need an
opener, because a double-click on its clip opens its editor.

## `paw.panes`

`paw.panes` tells a frontend where each pane of its main area goes
(`runtime/lua/paw/panes.tl`).

| Function | Effect |
| --- | --- |
| `paw.panes.area(width, height)` | Tells the kernel the size of the main area. The first time for a seat, the kernel shows the device panel beside the timeline. |
| `paw.panes.cells()` | The main area in cells, with the status line and the command line under it. |
| `paw.panes.state()` | The panes, the borders, the tabs (`tabs`, each `{ title }`), the current tab (`tab`), and `top`, where the panes start under the row of tabs. Nil before `area`. |
| `paw.panes.focus(win)` | Gives the window of a pane the keyboard, as a click in it does. |
| `paw.panes.pointer(win, event, drawn)` | A pointer event in a pane, as `paw.canvas.pointer` takes it. A press first gives the pane the keyboard. |
| `paw.panes.border(i, x, y)` | Moves border `i` of `state().borders` to `x, y`. A side with a size keeps a size in whole cells. |
| `paw.panes.close(win)` | Closes the window of a pane, as `:close` does. |
| `paw.panes.tab(i)` | Goes to tab `i`. |

The kernel sends the scene of a pane when the frontend tells its size in
cells (`scene.area`), and it takes the pointer in cells (`scene.input`). See
[Scenes](protocol.md#scenes).

## Views that paint

A view with a `paint` function draws in pixels. A frontend shows it in a
pane or in a window of its own, so an extension can bring its own editor to
the graphical window and the window needs no code for it.

```lua
paw.ui.view("scope", {
  paint = function(self, g, ctx)                 -- pixels; ctx.width, ctx.height
    local c = paw.canvas.palette                 -- the window's colors, by name
    g:rect(0, 0, ctx.width, ctx.height, { fill = c.surface })
    g:text(12, 10, "hello", { color = c.text, size = 14, bold = true })
    g:poly({ 0, 80, 40, 60, 80, 90 }, { color = c.select, width = 2 })
  end,
  pointer = function(self, e) end,               -- e.kind, e.x, e.y, e.button
})
paw.ui.dock("scope", { side = "bottom", hidden = true })
paw.canvas.open("scope", { title = "Scope", width = 640, height = 360 })
```

The painter `g` has the functions below.

| Method | Draws |
| --- | --- |
| `g:rect(x, y, w, h, style)` | A rectangle. |
| `g:text(x, y, text, style)` | Text. `style` has `color`, `size`, `bold`. |
| `g:line(x1, y1, x2, y2, style)` | A line. |
| `g:poly(points, style)` | A line through the points. `style` has `color`, `width`. |
| `g:sub(x, y, w, h)` | A painter for a part of the area. What it draws starts at its corner and is cut at its edges. A view scrolls with it. |
| `g:mono(x, y, text, style)` | A run of monospace cells. `style` has `color`, `background`. |
| `g:image(x, y, w, h, key)` | A picture of pixels that `paw.canvas.image` keeps, stretched to the rectangle. See [Pictures of pixels](pictures.md#pictures-of-pixels). |
| `g:glyph(x, y, size, codepoint, color, font)` | A glyph of a SMuFL music font in the program (Leland, Bravura, Petaluma), `size` pixels to the em. |
| `g:layer(name)` | Starts a layer: the page's `"ink"`, or what moves over it (`"selection"`, `"caret"`, `"ghost"`, `"diagnostic"`, `"playhead"`). A frontend can keep the page and draw the other layers over it. Draws nothing. |
| `g:cut(x, y0, y1)` | A barline at `x`, across `y0` to `y1` (a system): where a frontend can cut the page into images. Draws nothing. |

Colors are `#rrggbb` or `#rrggbbaa`.

The `ctx` table has the fields below.

| Field | Value |
| --- | --- |
| `width`, `height` | The size of the area in pixels. |
| `focused` | True when the view has the keyboard. |
| `surface` | True when the drawing goes to a terminal that shows images. |
| `cell` | The terminal's cell size `{ w, h }` in pixels, with `surface`. |
| `fg`, `bg` | The terminal's colors, with `surface`, or nil. |

The pointer event `e` has the fields below.

| Field | Value |
| --- | --- |
| `kind` | `down`, `up`, `move` (a button held), `hover` (no button held), `double`, `wheel`. |
| `x`, `y` | The position in pixels. |
| `button` | The button. |
| `ctrl`, `shift`, `alt` | The modifier keys. |
| `dx`, `dy` | The distance of the wheel. |

Keys go to the view's key mappings, or to its `on_key`, as in the terminal.

Buttons and the places that the pointer acts on go in a hit list. A
view that has one in `view.hits` gets the pointer there first, and the place
that the view painted last gets the event. The view's `pointer` gets the
events that no place takes. Each button does what a key of the view
does, so the terminal has the same action.

```lua
view.hits = paw.canvas.hit_list()
function view:paint(g, ctx)
  view.hits:clear()
  local x = paw.canvas.button(g, view.hits, 12, 8, "Play", function() paw.cmd("play") end)
  paw.canvas.button(g, view.hits, x, 8, "Loop", toggle_loop, { on = paw.transport.loop_enabled })
  view.hits:add(g, 0, 40, ctx.width, 30, { down = choose_row, double = open_row })
end
```

| Function | Effect |
| --- | --- |
| `paw.canvas.hit_list()` | A new hit list. `:clear()` removes the places of the paint before. |
| `hits:add(g, x, y, w, h, on)` | A place, from the corner of the painter `g`. `on` is a function for a press, or a table of `down`, `drag`, `up`, `double`, `wheel` and `right`. |
| `hits:under(x, y)` | The place under a point, or nil. |
| `hits:pointer(e)` | Gives an event to the place under it, or to the place where a drag started. True when a place takes it. |
| `paw.canvas.button(g, hits, x, y, label, action, opts)` | Paints a button and adds it to `hits`. `opts` has `width`, `height`, `fill`, `color`, `on` (lit) and `size`. Returns the `x` of the next button. |

| Function | Effect |
| --- | --- |
| `paw.canvas.open(name, opts)` | Shows a view that paints. A view that docks (`paw.ui.dock`, or a view with a window in the layout) shows in its pane, under `opts.title`. A view with no place in the layout, or with `opts.window = true`, shows in a window of its own of `opts.width` by `opts.height`. |
| `paw.canvas.open_view(name)` | Shows any view in a window of its own, drawn cell by cell as the terminal draws it. |
| `paw.canvas.windows()` | The views in windows of their own. |
| `paw.canvas.palette` | The window's colors, by the names of the window's own drawing: `surface`, `lane`, `panel`, `well`, `control`, `line_bar`, `text`, `text_2`, `text_3`, `select`, `play`, `rec`, `mute`, `solo`, `warn`, `error`, the meter colors and the colors of a keyboard. |
| `paw.canvas.glyph_outline(font, codepoint)` | The outline of a glyph as a path, for a frontend that cannot draw the glyphs of a music font. |
| `paw.api.smufl(font)` | The metadata of a SMuFL font: engraving defaults, glyph boxes and anchors, glyph names. |
| `paw.api.canvas_export(path, format, pages)` | Writes drawings to a file. `"pdf"` writes a page for each `{ ops, width, height }`. `"svg"` and `"png"` write the first page. Glyphs and text are outlines. |
| `paw.api.ui_view_snapshot(name, width, height)` | The cells of a view as rows of runs `{ x, w, text, fg, bg, attrs }`. |

The kernel paints the view at the size of the pane or the window. The
frontend makes the rectangles, text, lines and glyphs into one image with
the rasterizer of the terminal ([crates/paw-raster](../../crates/paw-raster)),
so the two frontends show the same pixels.

A view that also shows its pixels in the terminal keeps cells for them in
its `render` with `buf:surface(x, y, w, h)`, which returns false where the
terminal shows only cells (see [Pictures in the terminal](pictures.md)). A view that draws cells can also keep strips
for a part of itself, each drawn by a function, with
`buf:strip(x, y, w, h, { key, draw, under })`. `paw.plot` draws curves over
time in them (see [Pictures in the
terminal](pictures.md)).

The vocal editor of [extensions/utau](../../extensions/utau) is a view that
paints ([gui.lua](../../extensions/utau/lua/utau/gui.lua)), and it shows notes
with lyrics, the drawn pitch and the sung pitch, and phonemes. Its toolbar
has the singer, the tools and the grid.

## Kinds of part

The "+ Part" and "New part" menus offer each kind of part. The part
header shows the kind before the devices. A kind with an `editor` opens
its clips there on a double-click.
