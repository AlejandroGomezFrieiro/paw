//! `paw.api`: the screen: the grid, the frontends and drawing.

use std::rc::Rc;
use std::sync::Arc;

use mlua::{Function, Lua, LuaSerdeExt, LuaString, Table, Value as LuaValue};
use serde_json::{Value, json};
use unicode_width::UnicodeWidthStr;

use crate::grid::{self, Caps, Color, Grid, Highlight, Rect, Style, StyleId};

use super::{LuaText, Shared, cell, from_lua, to_lua};

/// A terminal's capabilities as Lua reads them (`paw.api.ui_caps`).
fn caps_lua(caps: &Caps) -> Value {
    let mut value = caps.to_json();
    value["cell"] = json!({ "w": caps.cell.0, "h": caps.cell.1 });
    value["pixels"] = json!(caps.pixels());
    value
}

fn parse_style(table: &Table) -> mlua::Result<Style> {
    let color = |key: &str| -> mlua::Result<Option<Color>> {
        Ok(match table.get::<LuaValue>(key)? {
            LuaValue::Nil => None,
            LuaValue::String(s) => {
                let text = s.to_str()?;
                Some(
                    Color::parse(&text)
                        .ok_or_else(|| mlua::Error::runtime(format!("bad colour `{}`", &*text)))?,
                )
            }
            LuaValue::Integer(i) => Some(Color::Indexed(i as u8)),
            LuaValue::Number(n) => Some(Color::Indexed(n as u8)),
            _ => {
                return Err(mlua::Error::runtime(format!(
                    "`{key}` must be a colour name, `#rrggbb` or 0-255"
                )));
            }
        })
    };
    let mut style = Style {
        fg: color("fg")?,
        bg: color("bg")?,
        on: 0,
        off: 0,
    };
    let attrs = [
        ("bold", grid::BOLD),
        ("dim", grid::DIM),
        ("italic", grid::ITALIC),
        ("underline", grid::UNDERLINE),
        ("reverse", grid::REVERSE),
        ("strike", grid::STRIKE),
    ];
    for (key, bit) in attrs {
        match table.get::<Option<bool>>(key)? {
            Some(true) => style.on |= bit,
            Some(false) => style.off |= bit,
            None => {}
        }
    }
    Ok(style)
}

/// A style given as the number of a highlight group (`hl_id`), its name, a
/// table of attributes, or nil. The number is what a frame passes: it costs
/// no look-up of a name.
fn style_of(shared: &Shared, value: &LuaValue) -> mlua::Result<Style> {
    let by_id = |id: f64| {
        let known = id >= 0.0 && id <= f64::from(u32::MAX);
        known
            .then(|| shared.highlights.borrow().style(StyleId(id as u32)))
            .flatten()
            .ok_or_else(|| mlua::Error::runtime(format!("no highlight group numbered {id}: see `hl_id`")))
    };
    match value {
        LuaValue::Nil => Ok(Style::default()),
        LuaValue::Integer(id) => by_id(*id as f64),
        LuaValue::Number(id) => by_id(*id),
        LuaValue::String(name) => Ok(shared.highlights.borrow().get(&name.to_str()?)),
        LuaValue::Table(table) => parse_style(table),
        _ => Err(mlua::Error::runtime(
            "a style must be a highlight group's number or name, or a table",
        )),
    }
}

/// Draw the UI by calling the Lua runtime's `render(width, height)`.
///
/// Lua draws through `api.grid_text` and `api.grid_fill`. There is deliberately
/// no drawing-buffer object: `paw.api` only ever passes plain data, so nothing
/// Lua holds can keep kernel state alive or outlive a reload.
///
/// Do not hand Lua a Rust type through `mlua::UserData` without checking this
/// first: with mlua 0.12.2 and LuaJIT on x86-64, collecting such an object
/// crashes. The finalizer mlua installs for those types returns its `int` with
/// the upper half of the register undefined, and LuaJIT's interpreter reads
/// all 64 bits. `tests/suite.lua` forces a collection after drawing to catch
/// a regression.
pub fn render(lua: &Lua, shared: &Shared) -> mlua::Result<()> {
    let (width, height) = {
        let grid = shared.grid.borrow();
        (grid.width, grid.height)
    };
    let paw: Table = lua.globals().get("paw")?;
    let kernel: Table = paw.get("_kernel")?;
    kernel.get::<Function>("render")?.call((width, height))
}

/// Draw only the live parts of the frame drawn last again (see
/// [`crate::grid::Live`]). False when the runtime finds that the frame needs
/// drawing whole: something not live moves.
pub fn render_live(lua: &Lua, shared: &Shared) -> mlua::Result<bool> {
    let (width, height) = {
        let grid = shared.grid.borrow();
        (grid.width, grid.height)
    };
    let paw: Table = lua.globals().get("paw")?;
    let kernel: Table = paw.get("_kernel")?;
    kernel.get::<Function>("render_live")?.call((width, height))
}

/// One view drawn by itself, as a window shows it: its grid, where it put
/// the cursor, and the theme's text and background colours.
pub(crate) type Drawn = (Grid, Option<(u16, u16)>, (u8, u8, u8), (u8, u8, u8));

/// Draw one view by itself on a grid of its own, as a window shows it, with
/// the colours of the theme in 24 bits, whatever the terminal shows. The
/// screen, its cursor and whether it needs drawing are left as they were.
pub(crate) fn draw_view(lua: &Lua, sh: &Shared, name: &str, width: u16, height: u16) -> mlua::Result<Drawn> {
    let screen = sh.grid.replace(Grid::new(width, height));
    let (cursor, dirty, redraws) = (sh.cursor.replace(None), sh.dirty.get(), sh.redraws.get());
    sh.highlights.borrow_mut().full_colour = true;
    let drawn = (|| {
        let paw: Table = lua.globals().get("paw")?;
        let kernel: Table = paw.get("_kernel")?;
        kernel.get::<Function>("render_view")?.call::<()>((name, width, height))
    })();
    let normal = sh.highlights.borrow().get("Normal");
    sh.highlights.borrow_mut().full_colour = false;
    let grid = sh.grid.replace(screen);
    let at = sh.cursor.replace(cursor);
    sh.dirty.set(dirty);
    sh.redraws.set(redraws);
    drawn?;
    let fg = grid::rgb(normal.fg.unwrap_or(Color::Default), (0xd8, 0xd9, 0xdc));
    let bg = grid::rgb(normal.bg.unwrap_or(Color::Default), (0x18, 0x19, 0x1c));
    Ok((grid, at, fg, bg))
}

/// [`draw_view`] as rows of runs of one style (see [`Grid::runs`]).
fn view_snapshot(lua: &Lua, sh: &Shared, name: &str, width: u16, height: u16) -> mlua::Result<Value> {
    let (grid, at, fg, bg) = draw_view(lua, sh, name, width, height)?;
    Ok(serde_json::json!({
        "width": width,
        "height": height,
        "fg": grid::hex(fg),
        "bg": grid::hex(bg),
        "rows": grid.runs(fg, bg),
        "cursor": at.map(|(x, y)| serde_json::json!({ "x": x, "y": y })),
    }))
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- screen ---
        // @return nil
        fn ui_redraw(_, sh, () => ()) {
            sh.dirty.set(true);
            sh.redraws.set(sh.redraws.get() + 1);
            Ok(())
        }
        // @return integer
        fn ui_redraws(_, sh, () => ()) { Ok(sh.redraws.get()) }
        // Tell paw which part of the song each window shows: a list of ranges of
        // beats, each with the tracks shown (all tracks when `tracks` is nil). The
        // stretched clips there bake before the others. paw.derived sends this
        // after each frame.
        // @param ranges {types.ViewRange}
        // @return nil
        fn view_ranges_set(lua, sh, ranges => LuaValue) {
            sh.session.borrow_mut().view_ranges_set(from_lua(lua, ranges)?);
            Ok(())
        }
        // The ranges that `view_ranges_set` gave last.
        // @return {types.ViewRange}
        fn view_ranges(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().view_ranges()) }
        // The prompt on the command line changed: draw its live parts again
        // (the line and the list), on the frame drawn last, and tell the
        // windows that show state that something moved. Cheaper than
        // `ui_redraw`: the views under it are not drawn again.
        // @return nil
        fn ui_redraw_line(_, sh, () => ()) {
            sh.live_dirty.set(true);
            sh.redraws.set(sh.redraws.get() + 1);
            sh.line_redraws.set(sh.line_redraws.get() + 1);
            Ok(())
        }
        // How many of the redraws (`ui_redraws`) were `ui_redraw_line`.
        // @return integer
        fn ui_line_redraws(_, sh, () => ()) { Ok(sh.line_redraws.get()) }
        // Draw only the live parts of the screen again (the playhead, the
        // meters, the status line), on the frame drawn last; a whole frame
        // when one is asked for too, or the runtime says it is needed.
        // @return nil
        fn ui_redraw_live(_, sh, () => ()) {
            sh.live_dirty.set(true);
            Ok(())
        }
        // The frames drawn so far: `{ full, live, unchanged }`: whole frames,
        // frames of the live parts only, and of those the ones that changed
        // no cell, which were not sent.
        // @return types.FrameCounts
        fn ui_frames(lua, sh, () => ()) {
            let [full, live, unchanged] = sh.frames.get();
            let t = lua.create_table()?;
            t.set("full", full)?;
            t.set("live", live)?;
            t.set("unchanged", unchanged)?;
            Ok(t)
        }
        // @return integer, integer
        fn ui_size(_, sh, () => ()) {
            let grid = sh.grid.borrow();
            Ok((grid.width, grid.height))
        }
        // @return boolean
        fn ui_attached(_, sh, () => ()) { Ok(sh.attached.get()) }
        // @return nil
        fn ui_cursor(_, sh, (x, y) => (Option<f64>, Option<f64>)) {
            sh.cursor.set(x.zip(y).map(|(x, y)| (x.max(0.0) as u16, y.max(0.0) as u16)));
            Ok(())
        }
        // True if the terminal reports the pointer (`paw.opt.mouse`), for the
        // screen that paw draws now.
        // @return nil
        fn ui_mouse(_, sh, on => bool) {
            sh.grid.borrow_mut().mouse_off = !on;
            Ok(())
        }
        // What the terminal of the seat whose turn it is can show besides
        // cells: `{ graphics, pixels, cell = { w, h }, pixel_mouse, fg, bg }`,
        // `pixels` when a view can be shown in pixels there.
        // @return types.Caps
        fn ui_caps(lua, sh, () => ()) {
            let caps = sh.caps.borrow().get(&sh.seat.get()).copied().unwrap_or_default();
            to_lua(lua, &caps_lua(&caps))
        }
        // Say what that terminal can show, in the same form: its frontend
        // does when it starts, and tests do.
        // @param caps types.Caps
        // @return nil
        fn ui_caps_set(lua, sh, caps => LuaValue) {
            let mut value: Value = lua.from_value(caps)?;
            // An empty table comes as an empty list.
            if value.as_array().is_some_and(Vec::is_empty) {
                value = json!({});
            }
            let Some(fields) = value.as_object_mut() else {
                return Err(mlua::Error::runtime("ui_caps_set takes a table: { graphics, pixels, cell = { w, h }, … }"));
            };
            let cell = fields.get("cell").map_or((Value::Null, Value::Null), |c| (c["w"].clone(), c["h"].clone()));
            fields.insert("cell".into(), json!([cell.0, cell.1]));
            sh.caps.borrow_mut().insert(sh.seat.get(), Caps::from_json(&value));
            sh.dirty.set(true);
            Ok(())
        }
        // Keep the cells `(x, y, w, h)`, clipped to `(cx, cy, cw, ch)`, for pixels
        // under the name `key` (`buf:strip`), over the text or `under` it.
        // Returns the number of the surface for `grid_surface_ops`, or nil when
        // no part of it is on the screen.
        // @return integer
        fn grid_surface(_, sh, (key, x, y, w, h, cx, cy, cw, ch, under) => (String, f64, f64, f64, f64, f64, f64, f64, f64, Option<bool>)) {
            let cell_px = sh.caps.borrow().get(&sh.seat.get()).map_or((0, 0), |c| c.cell);
            let clip = Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) };
            let whole = Rect { x: cell(x), y: cell(y), w: cell(w), h: cell(h) };
            Ok(sh.grid.borrow_mut().surface_part(&key, whole, clip, cell_px, under.unwrap_or(false)).map(|i| i + 1))
        }
        // The view being drawn is done with the surfaces it kept: what is
        // drawn over them from now on covers them.
        // @return nil
        fn grid_surfaces_seal(_, sh, () => ()) {
            sh.grid.borrow_mut().seal_surfaces();
            Ok(())
        }
        // The drawing a surface shows: the operations of `paw.canvas.paint`.
        // @return nil
        // @param ops {types.CanvasOp}
        fn grid_surface_ops(lua, sh, (index, ops) => (usize, LuaValue)) {
            let ops: Value = lua.from_value(ops)?;
            if let Some(surface) = sh.grid.borrow_mut().surfaces.get_mut(index.wrapping_sub(1)) {
                surface.ops = Arc::new(ops);
            }
            Ok(())
        }
        // A live part of the screen is drawn over the cells `(x, y, w, h)`,
        // clipped to `(cx, cy, cw, ch)`: what is under them is kept, to draw
        // it again by itself (`paw.ui.render_live`). Returns its number for
        // `grid_live_end`, or nil when no part of it is on the screen.
        // @return integer
        fn grid_live_begin(_, sh, (x, y, w, h, cx, cy, cw, ch) => (f64, f64, f64, f64, f64, f64, f64, f64)) {
            let clip = Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) };
            let area = Rect { x: cell(x), y: cell(y), w: cell(w), h: cell(h) };
            Ok(sh.grid.borrow_mut().live_begin(area.intersect(&clip)).map(|i| i + 1))
        }
        // @return nil
        fn grid_live_end(_, sh, index => usize) {
            sh.grid.borrow_mut().live_end(index.wrapping_sub(1));
            Ok(())
        }
        // While the live parts are drawn again: the part `index` of the frame
        // drawn last did not change, so its cells come back as they were, in
        // place of a `grid_live_begin` and `grid_live_end`. Returns its number,
        // or nil when it must be drawn (a part before it changed what is
        // under it).
        // @return integer
        fn grid_live_keep(_, sh, index => usize) {
            Ok(sh.grid.borrow_mut().live_keep(index.wrapping_sub(1)).map(|i| i + 1))
        }
        // In place of drawing the live parts again: none of them changed, so
        // the frame drawn last stays as it is, and nothing is sent.
        // @return nil
        fn grid_live_still(_, sh, () => ()) {
            sh.grid.borrow_mut().live_still();
            Ok(())
        }
        // The frame is drawn: what is over the live parts now stays over them.
        // @return nil
        fn grid_live_seal(_, sh, () => ()) {
            sh.grid.borrow_mut().live_seal();
            Ok(())
        }
        // Take the live parts off the frame drawn last, to draw them again.
        // Returns how many there were.
        // @return integer
        fn grid_live_restore(_, sh, () => ()) {
            Ok(sh.grid.borrow_mut().live_restore())
        }
        // A music font's SMuFL metadata (`Leland`, the default, `Bravura` or
        // `Petaluma`): `engravingDefaults`, `glyphBBoxes`, `glyphsWithAnchors`
        // and `glyphs` (every glyph name with its code point). Nil for a
        // font there is none of.
        // @return types.Smufl
        fn smufl(lua, _sh, font => Option<String>) {
            match paw_raster::smufl(font.as_deref()) {
                Some(meta) => to_lua(lua, &meta),
                None => Ok(LuaValue::Nil),
            }
        }
        // A music font's glyph as path commands in staff spaces from its
        // origin, y down (`{ "M", x, y, "C", ... }`), for a frontend that
        // cannot draw the font. Nil for a glyph or font there is none of.
        // @return {string | number}
        fn smufl_outline(lua, _sh, (font, codepoint) => (Option<String>, u32)) {
            match paw_raster::glyph_outline(font.as_deref(), codepoint) {
                Some(path) => to_lua(lua, &serde_json::Value::from(path)),
                None => Ok(LuaValue::Nil),
            }
        }
        // Keep a picture of pixels for drawings to name (`paw.canvas.image`):
        // `bytes` a PNG file, or straight RGBA `w` by `h` pixels row by row;
        // `format` `"png"` or `"rgba"` (a PNG file is known without it). Returns
        // its content key, its width and its height.
        // @return string, integer, integer
        fn canvas_image(_, _sh, (bytes, w, h, format) => (LuaString, Option<u32>, Option<u32>, Option<String>)) {
            let pixmap = paw_raster::pixels::decode(&bytes.as_bytes(), format.as_deref(), w.zip(h))
                .map_err(|e| mlua::Error::runtime(e.to_string()))?;
            let (w, h) = (pixmap.width(), pixmap.height());
            Ok((paw_raster::pixels::keep(pixmap), w, h))
        }
        // A picture of pixels kept under `key`, as a window is sent it: its
        // size and its pixels as straight RGBA in base64. Nil for a key not
        // kept (any more).
        // @return types.PictureBlob
        fn canvas_pixels(lua, _sh, key => String) {
            match paw_raster::pixels::get(&key) {
                Some(pixmap) => to_lua(lua, &paw_raster::pixels::to_blob(&pixmap)),
                None => Ok(LuaValue::Nil),
            }
        }
        // Write drawings (the operations of `paw.canvas.paint`) to a file:
        // `format` "pdf" (one page for each drawing), "svg" or "png" (the first).
        // Each page is `{ ops, width, height }` in pixels. `scale` is the points
        // for one pixel in a PDF (0.75: 96 pixels to the inch).
        // @param pages {types.CanvasPage}
        // @return nil
        fn canvas_export(lua, _sh, (path, format, pages, scale) => (String, String, LuaValue, Option<f32>)) {
            let pages: Vec<Value> = lua.from_value(pages)?;
            let drawn: Vec<(paw_raster::Drawing, f32, f32)> = pages
                .iter()
                .map(|p| {
                    let size = |k: &str| p[k].as_f64().unwrap_or(1.0).max(1.0) as f32;
                    (paw_raster::Drawing::parse(&p["ops"]), size("width"), size("height"))
                })
                .collect();
            let Some((first, width, height)) = drawn.first() else {
                return Err(mlua::Error::runtime("nothing to write"));
            };
            let bytes = match format.as_str() {
                "pdf" => paw_raster::vector::pdf(&drawn, scale.unwrap_or(0.75)),
                "svg" => paw_raster::vector::svg(first, *width, *height).into_bytes(),
                "png" => first
                    .paint_all(*width as u32, *height as u32)
                    .and_then(|p| p.encode_png().ok())
                    .ok_or_else(|| mlua::Error::runtime("could not paint the drawing"))?,
                other => return Err(mlua::Error::runtime(format!("no format `{other}`: pdf, svg or png"))),
            };
            std::fs::write(&path, bytes).map_err(|e| mlua::Error::runtime(format!("{path}: {e}")))
        }
        // @param def string | types.CellStyle
        // @param full? string | types.CellStyle
        // @return nil
        fn hl_set(_, sh, (name, def, full) => (String, LuaValue, LuaValue)) {
            // `full` is the group in 24-bit colour, given when `def` is a
            // nearer form of it for a terminal that shows fewer colours.
            let parse = |def: &LuaValue| Ok(match def {
                LuaValue::String(link) => Highlight::Link(link.to_str()?.to_string()),
                LuaValue::Table(table) => Highlight::Style(parse_style(table)?),
                _ => return Err(mlua::Error::runtime("a highlight is a table of attributes or the name of another group")),
            });
            let highlight = parse(&def)?;
            // Kept cells have their colours: they are drawn again.
            sh.kept_cells.borrow_mut().clear();
            let mut highlights = sh.highlights.borrow_mut();
            highlights.set(&name, highlight);
            if !full.is_nil() {
                highlights.set_full(&name, parse(&full)?);
            }
            sh.dirty.set(true);
            sh.redraws.set(sh.redraws.get() + 1);
            Ok(())
        }
        // The number of the highlight group `name`, for the style of
        // `grid_text` and `grid_fill`: a frame passes numbers, not names.
        // The number stays the same for as long as paw runs, and follows
        // the group when it changes. A group not defined yet has one too.
        // @return integer
        fn hl_id(_, sh, name => LuaString) {
            Ok(sh.highlights.borrow_mut().id(&name.to_str()?).0)
        }
        // @return integer
        fn str_width(_, _sh, text => LuaText) { Ok(text.to_str()?.width()) }
        // @return {string}
        fn ui_snapshot(lua, sh, (width, height) => (u16, u16)) {
            // Draw the UI off screen at the given size and return it as lines
            // of text, for tests and for looking at the UI over the socket.
            let screen = sh.grid.replace(Grid::new(width, height));
            let cursor = sh.cursor.get();
            let drawn = render(lua, &sh);
            let grid = sh.grid.replace(screen);
            sh.cursor.set(cursor);
            // The runtime's list of live parts is of this drawing now: the
            // screen is drawn whole next.
            sh.dirty.set(true);
            drawn?;
            let lines: Vec<String> = grid
                .cells
                .chunks(width.max(1) as usize)
                .map(|row| row.iter().filter(|c| c.ch != '\0').map(|c| c.ch).collect::<String>())
                .map(|line| line.trim_end().to_string())
                .collect();
            Ok(lines)
        }
        // A frame drawn off screen as a terminal is drawn, for tests: whole,
        // or with `live` only its live parts again on the frame this drew
        // last (nil when the runtime says it must be drawn whole). Each
        // row as its text and as its cells with their styles.
        // @return types.FrameSnapshot
        fn ui_frame_snapshot(lua, sh, (width, height, live) => (u16, u16, Option<bool>)) {
            let mut frame = sh.snapshot.take().filter(|g| (g.width, g.height) == (width, height));
            let live = live.unwrap_or(false);
            if live && frame.is_none() {
                return Ok(LuaValue::Nil);
            }
            let screen = sh.grid.replace(frame.take().unwrap_or_else(|| Grid::new(width, height)));
            let (cursor, dirty) = (sh.cursor.get(), sh.dirty.get());
            let drawn = if live {
                render_live(lua, &sh)
            } else {
                sh.grid.borrow_mut().clear();
                render(lua, &sh).map(|()| true)
            };
            let grid = sh.grid.replace(screen);
            sh.cursor.set(cursor);
            // The runtime's list of live parts is of this drawing now: the
            // screen is drawn whole next.
            sh.dirty.set(dirty || !live);
            let drawn = drawn?;
            if !drawn {
                return Ok(LuaValue::Nil);
            }
            let rows = grid.cells.chunks(width.max(1) as usize);
            let text: Vec<String> = rows.clone().map(|row| row.iter().filter(|c| c.ch != '\0').map(|c| c.ch).collect()).collect();
            let cells: Vec<String> = rows.map(|row| row.iter().map(|c| format!("{:?}", c)).collect()).collect();
            let out = lua.create_table()?;
            out.set("text", text)?;
            out.set("cells", cells)?;
            out.set("live", grid.live.len())?;
            sh.snapshot.replace(Some(grid));
            Ok(LuaValue::Table(out))
        }
        // @return types.ViewSnapshot
        fn ui_view_snapshot(lua, sh, (name, width, height) => (String, u16, u16)) {
            // One view drawn by itself at the given size, as rows of runs of
            // one style: what a window shows of a view that draws cells.
            let snapshot = view_snapshot(lua, &sh, &name, width.max(1), height.max(1))?;
            to_lua(lua, &snapshot)
        }
        // Draw text at `(x, y)`, clipped to the rectangle `(cx, cy, cw, ch)`,
        // in `style`: the number of a highlight group (`hl_id`), its name,
        // a table of attributes, or nil. Returns the number of columns the
        // text takes.
        // @param style integer | string | types.CellStyle
        // @return integer
        fn grid_text(_, sh, (x, y, text, style, cx, cy, cw, ch) => (f64, f64, LuaText, LuaValue, f64, f64, f64, f64)) {
            let style = style_of(&sh, &style)?;
            let clip = Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) };
            let text = text.to_str()?;
            // Kept as a node too while a view is drawn for a scene.
            sh.scenes.borrow_mut().text(clip, cell(x), cell(y), &text, style);
            Ok(sh.grid.borrow_mut().text(clip, cell(x), cell(y), &text, style))
        }
        // Draw the picture of pixels kept under `key` over the cells `(x, y,
        // w, h)`, clipped to `(cx, cy, cw, ch)`, two pixels a cell in half
        // blocks (`▀`): what a terminal that shows no images shows of it.
        // False for a key not kept (any more).
        // @return boolean
        fn grid_image(_, sh, (key, x, y, w, h, cx, cy, cw, ch) => (String, f64, f64, f64, f64, f64, f64, f64, f64)) {
            let Some(pixmap) = paw_raster::pixels::get(&key) else { return Ok(false) };
            let clip = Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) };
            let area = Rect { x: cell(x), y: cell(y), w: cell(w), h: cell(h) };
            if area.w <= 0 || area.h <= 0 {
                return Ok(true);
            }
            let colour = |c: Option<paw_raster::Rgba>| c.map_or(Color::Default, |c| Color::Rgb(c.0, c.1, c.2));
            let halves = paw_raster::pixels::half_blocks(&pixmap, area.w as u32, area.h as u32);
            let (mut grid, mut scenes) = (sh.grid.borrow_mut(), sh.scenes.borrow_mut());
            for (i, [top, bottom]) in halves.into_iter().enumerate() {
                let (col, row) = (area.x + i as i32 % area.w, area.y + i as i32 / area.w);
                // The half that has a colour is the character's.
                let (ch, fg, bg) = match (top, bottom) {
                    (Some(_), _) => ("▀", top, bottom),
                    (None, Some(_)) => ("▄", bottom, None),
                    (None, None) => (" ", None, None),
                };
                let style = Style { fg: Some(colour(fg)), bg: Some(colour(bg)), ..Style::default() };
                scenes.text(clip, col, row, ch, style);
                grid.text(clip, col, row, ch, style);
            }
            Ok(true)
        }
        // Keep the cells of the area `(x, y, w, h)`, clipped to `(cx, cy,
        // cw, ch)`, under `key`, to put back on a later frame with
        // `grid_put` when what they were drawn from has not changed.
        // @return nil
        fn grid_keep(_, sh, (key, x, y, w, h, cx, cy, cw, ch) => (String, f64, f64, f64, f64, f64, f64, f64, f64)) {
            let area = Rect { x: cell(x), y: cell(y), w: cell(w), h: cell(h) }
                .intersect(&Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) });
            let kept = sh.grid.borrow().keep(area);
            let mut all = sh.kept_cells.borrow_mut();
            match kept {
                Some(kept) => all.insert(key, kept),
                None => all.remove(&key),
            };
            Ok(())
        }
        // Put the cells kept under `key` back, if they were kept from the
        // same area: true when they were. Nothing is drawn else.
        // @return boolean
        fn grid_put(_, sh, (key, x, y, w, h, cx, cy, cw, ch) => (String, f64, f64, f64, f64, f64, f64, f64, f64)) {
            let area = Rect { x: cell(x), y: cell(y), w: cell(w), h: cell(h) }
                .intersect(&Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) });
            let all = sh.kept_cells.borrow();
            Ok(all.get(&key).is_some_and(|kept| sh.grid.borrow_mut().put_kept(area, kept)))
        }
        // Restyle the area `(x, y, w, h)`, clipped to `(cx, cy, cw, ch)`, in
        // `style` as `grid_text` takes it, and overwrite its characters when
        // `fill` is given.
        // @param style integer | string | types.CellStyle
        // @return nil
        fn grid_fill(_, sh, (x, y, w, h, fill, style, cx, cy, cw, ch) => (f64, f64, f64, f64, Option<LuaText>, LuaValue, f64, f64, f64, f64)) {
            let style = style_of(&sh, &style)?;
            let fill = match fill {
                Some(s) => s.to_str()?.chars().next(),
                None => None,
            };
            let clip = Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) };
            let area = Rect { x: cell(x), y: cell(y), w: cell(w), h: cell(h) };
            sh.scenes.borrow_mut().fill(clip, area, fill, style);
            sh.grid.borrow_mut().fill(clip, area, fill, style);
            Ok(())
        }

    }
    Ok(())
}
