# Pictures in the terminal

<!-- tags: extensions-pictures-in-the-terminal graphics kitty-graphics strips -->

The pictures page describes how a view shows pixels in the terminal and in the graphical window, and it covers strips, pictures of pixels, `paw.plot`, and what a frontend does with strips. "What paw asks the terminal" below explains how paw finds out which terminals show pictures.

## Strips

A view that draws cells can show a part of itself in pixels. In its `render`, the view keeps a strip of cells, tells paw how to draw the strip, and also draws its cells as usual.

```lua
render = function(self, buf, ctx)
  local plot = buf:sub(10, 2, buf.width - 10, buf.height - 3)
  plot:fill(0, 0, plot.width, plot.height, " ", "Lane")
  local pictured = plot:strip(0, 0, plot.width, plot.height, {
    key = "mylane:" .. ctx.win.id,       -- the name of the strip: one for each window
    under = true,                         -- the cells drawn here stay, above the picture
    draw = function(g, px)                -- after the screen is drawn. px: w, h, cell = { w, h }, fg, bg
      paw.plot.curve(g, px, { points = points, from = left, pixels_per_beat = zoom * px.cell.w,
        lo = 0, hi = 1, color = paw.draw.part_colour(part) })
    end,
  })
  if not pictured then draw_the_curve_in_cells(plot) end
  draw_the_cursor_and_points(plot)       -- cells, over the picture or alone
end
```

`buf:strip(x, y, w, h, opts)` returns false where there are no pixels, which happens when `paw.opt.graphics` is off, when the terminal shows no images, in tmux, and in `paw attach` from such a terminal. The view then draws its cells there.

| Option | Effect |
| --- | --- |
| `key` | the name of the strip, and of the images that the terminal keeps. The default is the view and its window, and a view with more than one strip names each strip |
| `under` | with true, the picture is under the text, and the backgrounds of the cells show where the picture draws nothing. With false, the cells of the strip are blank |
| `draw(g, px)` | draws the pixels with a painter of `paw.canvas` (`g:rect`, `g:poly`, `g:text`, `g:cut`, `g:layer`, as in `paint`) |

- In a terminal where a colored background hides the picture (Konsole), paw paints the backgrounds of the cells into the picture, and a background that is one run along one row (a cursor block, the note under the cursor) stays a cell.
- Draw a cursor that moves over the picture as such a block, or as a glyph (a line on the left edge of the cell), and do not draw it as a column of blocks.
- A strip can extend past its window, e.g., an audio clip that is half out of view. `px.w` and `px.h` are then the size of the full strip, drawn from its own corner, and `px.view` (`x`, `y`, `w`, `h`) is the part that shows.
- `paw.plot.span(px, step)` gives the part to draw, in whole steps from the left of the strip. A part drawn before is the same after a scroll, so paw moves its pieces and does not send them again.
- The frontend makes the pixels, cuts them into pieces at the `g:cut` marks of the drawing, and keeps each piece by the hash of its pixels. A strip that draws the same pixels again sends nothing, and an edit sends only the pieces that it changed.
- `buf:surface(x, y, w, h)` does the same over the text, for the full `paint` of a view.

## Pictures of pixels

A view can show a picture of pixels, e.g., a frame of a video, a spectrogram or a cover. paw keeps the picture under a key, and the view shows it by its key.

```lua
local f = assert(io.open("cover.png", "rb"))
local key, w, h = paw.canvas.image(f:read("*a"))   -- PNG, or RGBA with its size
f:close()

render = function(self, buf, ctx)
  buf:image(0, 0, buf.width, buf.height, key)      -- in cells
end

paint = function(self, g, ctx)
  g:image(0, 0, ctx.width, ctx.height, key)        -- in pixels
end
```

| Function | Effect |
| --- | --- |
| `paw.canvas.image(bytes, w, h, format)` | Keeps a picture. `bytes` is a PNG file, or straight RGBA of `w` by `h` pixels, row by row. `format` is `"png"` or `"rgba"`. paw knows a PNG file without it. Returns the key, the width and the height |
| `buf:image(x, y, w, h, key)` | Shows the picture over the cells. Where the terminal or the window shows images, it is a strip under the cells, and otherwise paw writes half blocks (`▀`), two pixels in each cell, in the colors of the picture. Returns true where it is an image, as `buf:strip` does |
| `g:image(x, y, w, h, key)` | Paints the picture over the rectangle in pixels. What is outside the painter is cut off |

- The key comes from the pixels, so the same pixels have the same key, and a frontend that has a picture does not get it again. The terminal keeps each piece of a strip by the hash of its operations, so a picture that did not change sends no pixels.
- A picture stretches to the rectangle. When the rectangle is larger than the pixels, each pixel shows as a block, and when it is smaller, the pixels mix.
- paw keeps the pictures that views used last, up to 256 MB. A picture that paw does not keep any more draws nothing, and you keep it again with `paw.canvas.image`.
- SVG and PDF files that `paw.canvas` writes do not contain the pictures.

## `paw.plot`

`paw.plot` draws in strips what views show over time, with the same appearance in all views.

`paw.plot.curve(g, px, opts)` draws a curve, and the drawing has these parts:

- the lines of the bars and beats, from the tempo map of the window's time (`paw.draw.bar_lines`), cut at each bar on the edge of a cell
- the area under the curve, and the line, with one sample for each pixel from `paw.curves.value_at`
- a small mark at each point

It draws no background unless `opts.background` gives one, so the backgrounds of the cells show under the text. It returns `x(beat)` and `y(value)` for the rest of the drawing.

| Option | Value |
| --- | --- |
| `points` | the points, as `paw.curves` gives them |
| `from` | the beat at the left |
| `pixels_per_beat` | the zoom |
| `frac(value)`, or `lo` and `hi` | the value as 0 to 1 |
| `flat`, `color`, `fill` (the opacity of the area), `width`, `top`, `bottom` | the appearance |
| `grid`, `beats`, `guides`, `markers`, `background` | what else to draw |
| `shape = "hold"` | each value holds until the next point |

The curve editor (`paw.curves.editor.picture`), the controller strip of the piano roll (with `shape = "hold"`) and the curve of the utau editor use `paw.plot.curve`.

| Function | Draws |
| --- | --- |
| `paw.plot.lines(w, from, pixels_per_beat, cell_w)` | the lines of the bars and the beats only |
| `paw.plot.bars(g, px, opts)` | a bar from the bottom for each of `opts.items`, `{ beat, value, color, bright }`, with `value` from 0 to 1. The options are `from`, `pixels_per_beat`, `width` and `color` |
| `paw.plot.wave(g, px, opts)` | a waveform. `opts.peaks(n)` gives `n` values `{ min, max, rms }` across the strip (`api.clip_peaks`), and the RMS is a brighter band inside (`rms`, false for none). A column at full scale is in `clipped` (red). The scale is `paw.opt.wave_scale`, and the function draws in parts of eight cells. The arrange view draws its audio clips this way |

Each function has a version in cells, for where there are no pictures, and the version takes the same options, with `zoom` (cells for each beat) in place of `pixels_per_beat`.

| Function | Cells |
| --- | --- |
| `paw.plot.curve_cells(buf, opts)` | connected sextants (`paw.opt.curve_glyphs`) |
| `paw.plot.bars_cells(buf, opts)` | eighth blocks |
| `paw.plot.wave_cells(buf, opts)` | `paw.draw.waveform` |

## What a frontend does with strips

A frontend that draws the screen itself (a remote terminal) gets the grid of cells and its strips. Each strip is a `Surface` (`crates/paw-core/src/grid.rs`), and over `paw attach` the strips are the `surfaces` of `ui.grid` (`crates/paw-core/src/remote.rs`).

| Field | Meaning |
| --- | --- |
| `key` | the name of the strip, where you keep what you make of it (images, textures) by key and drop it when a frame has no strip with that key |
| `rect` | the cells of the screen that the strip shows |
| `whole` | the size of the full strip in cells, when a part is off its window. (0, 0) when all of it shows |
| `offset` | the cells of the strip to the left of `rect` and above it |
| `cell` | the size of a cell in pixels, for the drawing |
| `ops` | the drawing, in pixels from the corner of the full strip: the operations of `paw.canvas` (`r` rectangles, `p` paths, `t` text, `m` runs of cells, `g` music glyphs, `i` pictures of pixels by their key, `cut` where it can be cut into pieces, `layer` for what comes next) |
| `under` | with false, the cells of the strip are blank and the picture is over all of `rect`, and with true, you draw the picture after the backgrounds of the cells and before their text |
| `covered` | a flag for each cell, row by row (`covered_runs` over the wire), for cells that something draws over the strip later (a menu, a floating view), and you do not draw the picture in them |

- Draw `ops` with `paw_raster::Drawing`, or with the painter of the frontend, scale by the cell size of the frontend over `cell`, translate by `-offset * cell`, and clip to `rect`.
- With `under` true, the characters of the view (its cursor, points, labels, the playhead) are over the picture, and the backgrounds of the cells show where the picture draws nothing.
- A frontend that paints its pictures in pieces (the terminal does, with the kitty protocol) cuts the full strip at the `cut` marks and keeps each piece by the hash of the operations in it (`Drawing::piece_key`). It does not make a piece again when the piece did not change, or only moved.

### In the graphical window

The graphical window (`crates/paw-gui`, on egui) does not get the grid. A view that it shows in a pane, or in a window of its own, comes as a scene (`crates/paw-scene`, and "Scenes" in [The control protocol](protocol.md)).

- `paw.ui.render_scene(name, w, h, cell, win)` makes the scene from the writes of the view, where each `buf:text` is a run and each `buf:fill` is a fill, kept by place, and paw sends what changed.
- While paw draws the view for a scene, `buf:strip` keeps each strip under the text (`paw.ui.pictures`) and returns true. The `draw(g, px)` of the strip, at the cell size of the window, is a picture of the scene, cut to the part that shows (`px.view`).
- The window draws the backgrounds of the cells first, then the pictures under the text, and then the text in its own font. A view that paints is one picture.
- A picture of pixels in a drawing (`i`) comes by its key, and the window asks for its pixels once (`scene.pixels`) and keeps them.
- The curve editor and the vocal editor therefore show curves in pixels in the window, and nothing in `crates/paw-gui` knows about strips.
- The scene is made from the writes of the view, so a view must draw only through the buffer that it gets. `tests/scene_parity.lua` checks each view, the views of extensions too, and it also checks that the scene, lowered to cells, is the drawing of the view.
- A view that the window draws natively (the arrange view, the piano roll, the mixer) draws its curves and waveforms with the painter of egui, and it has no strips.

## Pictures in each terminal

A view that paints for the graphical window (`paint`, see [The graphical frontend](window.md)) shows the same pixels in a terminal that shows images, e.g., the score of `:notation`.

### What paw asks the terminal

At the start, paw asks the terminal what it is (XTVERSION), what its colors are (`OSC 10` and `11`), and how large a cell is in pixels. It also asks whether the terminal shows images with the kitty graphics protocol and how it takes them, which is through shared memory, a temporary file, or in the escape sequences, and whether it reports the pointer in pixels (mode 1016).

The log gives the result, in a line that starts with `terminal:`.

### Strips

A picture is a strip, which is a rectangle of cells that a view keeps for pixels when it draws (`buf:strip`, see [Pictures in the terminal](pictures.md)). A strip has a key of its own, so a view can have several strips, and the same view in two windows (`:vs`) has a separate strip in each.

| View | Strips |
| --- | --- |
| Score (`:notation`) | one strip over its window |
| Curve editor (`gC`) | the plot |
| Piano roll | the controller strip (the pitch wheel and the controllers) |
| Arrange view | one strip for each audio clip: the lowest to the highest sample for each pixel, the RMS as a brighter band inside, full scale in red |
| Vocal editor (utau) | two strips: the pitch lines under its notes, and its curve |

The strip of an audio clip is the strip of the whole clip, so when you scroll, paw moves pieces that it sent before and does not send them again.

A strip is over the text or under it.

- A strip over the text has blank cells, as the score does.
- For a strip under the text, the cells of the view show as usual above the picture. The curve editor keeps its points, its cursor, the selection and the playhead as cells, while the grid, the line and the area under the line are pixels, with a sample for each pixel, and nothing of the curve shows two times.

### How paw sends a picture

paw makes the picture at the cell size of the terminal and cuts it into pieces at its barlines, and an edit sends again only the bars that it changes. A menu or a float over a part of the picture hides the pieces under it.

What moves over the page (the cursor, the next note, the playhead) is a picture of its own above the page. paw does this in the terminals that put images over images well, which are kitty, Ghostty, and herdr (which answers as libghostty). In other terminals, WezTerm among them, paw draws the moving parts into the pieces that they cross.

A strip under the text is at a z of -2, and the parts that move are at -1.

- In kitty, Ghostty, herdr and WezTerm, the text shows above the picture, and the picture above the colored backgrounds of the cells, so the backgrounds show where the picture draws nothing.
- Konsole, and each terminal not known by its name, puts a colored background above such a picture, which hides it. There, paw paints the backgrounds of the cells (the lane, the notes, a selection) into the picture and writes the cells on the background of the terminal. A background that is one run along one row (a cursor block, the note under the cursor) shows as cells, and the picture keeps there what those cells had before, so a cursor that moves sends no pixels.

Over a picture, the pointer goes to the view in pixels where the terminal reports them, and otherwise it goes to the middle of the cell.

### Where there are no pictures

`paw attach` from a terminal that shows images shows them too, and it tells the instance what its terminal can do. The instance sends the drawing of each strip (only when it changes), and `paw attach` makes the pixels. It asks the instance one time for each picture of pixels that a drawing names (`scene.pixels`).

Where the terminal shows no images, the view draws in cells. The view draws in cells in tmux (which does not send images through), in a terminal without the protocol, and in `paw attach` from such a terminal. `:set graphics!` (`paw.opt.graphics = false`) keeps cells everywhere, and the same command again gives the pictures back.
