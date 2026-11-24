//! The terminal UI shown somewhere else: the kernel's screen sent over a
//! connection as the cells that changed, and put together again there.
//!
//! `ui.attach` makes a connection a frontend like the program's own
//! terminal: after every turn that changed the screen it is pushed a
//! `ui.grid` event,
//!
//!   { "w": 120, "h": 40, "full": false, "cursor": [x, y] or null,
//!     "runs": [ [x, y, "text", fg, bg, attrs], ... ], "mouse": true }
//!
//! where a run is a stretch of cells of one style on one row, colours are
//! `null` (the terminal's own), a number (one of its 256) or `"#rrggbb"`,
//! and `attrs` are the bits of [`crate::grid`]. `full` says that the screen
//! is to be cleared first (the first event, and after a change of size).
//! `mouse` false asks the terminal to leave the pointer to its own
//! selection (`paw.opt.mouse` off).
//!
//! A terminal that said with `ui.attach` that it shows images (its third
//! parameter, `{ "graphics": true, "cell": [w, h], ... }`, see
//! [`crate::grid::Caps`]) is also sent the surfaces views show pixels in,
//!
//!   "surfaces": [ { "key": "notation#3", "x": 0, "y": 3, "w": 80, "h": 30,
//!                   "cell": [10, 20], "under": false,
//!                   "covered": [[col, row, cols], ...], "ops": [...] }, ... ]
//!
//! with `ops`, the drawing, only when it differs from what was last sent
//! for that key: the drawing travels, and the far side makes the pixels.
//! `under` places the pixels under the text, which is drawn there as usual.
//! A strip partly off its window has `"offset": [cols, rows]` (where what
//! shows is in the whole) and `"whole": [cols, rows]`, and its drawing is
//! of the whole.
//! The other side keeps a [`Grid`] and gives each event to [`apply`].
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use anyhow::{Result, bail};
use serde_json::{Value, json};

use std::sync::Arc;

use crate::grid::{Cell, Color, Grid, Rect, Style, Surface};
use crate::kernel::{Frontend, InputEvent};
use crate::rpc::{ClientId, Clients};

fn color_json(color: Color) -> Value {
    match color {
        Color::Default => Value::Null,
        Color::Indexed(index) => json!(index),
        Color::Rgb(r, g, b) => json!(format!("#{r:02x}{g:02x}{b:02x}")),
    }
}

fn color_of(value: &Value) -> Color {
    if let Some(index) = value.as_u64() {
        return Color::Indexed(index.min(255) as u8);
    }
    let hex = value.as_str().and_then(|s| s.strip_prefix('#'));
    match hex.and_then(|hex| u32::from_str_radix(hex, 16).ok()) {
        Some(rgb) => Color::Rgb((rgb >> 16) as u8, (rgb >> 8) as u8, rgb as u8),
        None => Color::Default,
    }
}

/// A run being gathered by [`runs`].
struct Run {
    /// Where it starts.
    x: usize,
    y: usize,
    /// The style of its cells (the first one's).
    cell: Cell,
    text: String,
    /// The column after its last cell.
    next: usize,
}

/// The cells of `grid` that differ from `shown` (all of them without it),
/// as runs of one style.
pub(crate) fn runs(grid: &Grid, shown: Option<&Grid>) -> Vec<Value> {
    let width = grid.width as usize;
    let mut out = Vec::new();
    let mut run: Option<Run> = None;
    let mut close = |run: &mut Option<Run>| {
        if let Some(Run { x, y, cell, text, .. }) = run.take() {
            out.push(json!([
                x,
                y,
                text,
                color_json(cell.fg),
                color_json(cell.bg),
                cell.attrs
            ]));
        }
    };
    for (index, cell) in grid.cells.iter().enumerate() {
        let (x, y) = (index % width.max(1), index / width.max(1));
        // The second half of a wide character goes with its first.
        if cell.ch == '\0' {
            if let Some(run) = &mut run {
                run.next = x + 1;
            }
            continue;
        }
        let wide = grid.cells.get(index + 1).is_some_and(|next| next.ch == '\0');
        let unchanged = shown.is_some_and(|shown| {
            shown.cells[index] == *cell
                && (!wide || shown.cells.get(index + 1).is_some_and(|c| c.ch == '\0'))
        });
        let joins = run.as_ref().is_some_and(|run| {
            run.y == y
                && run.next == x
                && (run.cell.fg, run.cell.bg, run.cell.attrs) == (cell.fg, cell.bg, cell.attrs)
        });
        if unchanged {
            close(&mut run);
            continue;
        }
        if !joins {
            close(&mut run);
            run = Some(Run { x, y, cell: *cell, text: String::new(), next: x });
        }
        if let Some(run) = &mut run {
            run.text.push(cell.ch);
            run.next = x + 1;
        }
    }
    close(&mut run);
    out
}

/// The largest width or height, in cells, of a screen or a surface that
/// arrives.
const MAX_CELLS: i32 = 1000;

/// Put a `ui.grid` event into the grid kept on the receiving side. Returns
/// where the cursor is.
pub fn apply(grid: &mut Grid, payload: &Value) -> Result<Option<(u16, u16)>> {
    let (Some(width), Some(height)) = (payload["w"].as_u64(), payload["h"].as_u64()) else {
        bail!("a screen without a size");
    };
    let (width, height) = (width.min(MAX_CELLS as u64) as u16, height.min(MAX_CELLS as u64) as u16);
    if payload["full"].as_bool().unwrap_or(false) || (grid.width, grid.height) != (width, height) {
        *grid = Grid::new(width, height);
    }
    grid.mouse_off = payload["mouse"].as_bool() == Some(false);
    let clip = grid.rect();
    for run in payload["runs"].as_array().into_iter().flatten() {
        let (Some(x), Some(y), Some(text)) = (run[0].as_i64(), run[1].as_i64(), run[2].as_str())
        else {
            continue;
        };
        let attrs = run[5].as_u64().unwrap_or(0) as u8;
        let style = Style {
            fg: Some(color_of(&run[3])),
            bg: Some(color_of(&run[4])),
            on: attrs,
            off: !attrs,
        };
        grid.text(clip, x as i32, y as i32, text, style);
    }
    let before = std::mem::take(&mut grid.surfaces);
    for s in payload["surfaces"].as_array().into_iter().flatten() {
        let number = |v: &Value| v.as_i64().unwrap_or(0) as i32;
        // The far side can send any number. A place stays where its sums
        // cannot overflow, and a size within the largest screen, so that
        // `covered` is not billions of cells.
        let place = |v: &Value| number(v).clamp(-MAX_CELLS, MAX_CELLS);
        let extent = |v: &Value| number(v).clamp(0, MAX_CELLS);
        let rect = Rect { x: place(&s["x"]), y: place(&s["y"]), w: extent(&s["w"]), h: extent(&s["h"]) };
        let key = s["key"].as_str().unwrap_or("").to_string();
        let ops = match s.get("ops") {
            Some(ops) => Arc::new(ops.clone()),
            // The same drawing as before.
            None => before.iter().find(|b| b.key == key).map(|b| b.ops.clone()).unwrap_or_default(),
        };
        let mut covered = vec![false; (rect.w * rect.h) as usize];
        for run in s["covered"].as_array().into_iter().flatten() {
            let (col, row, cols) = (number(&run[0]), number(&run[1]), number(&run[2]));
            if !(0..rect.h).contains(&row) {
                continue;
            }
            for c in col.max(0)..col.saturating_add(cols).min(rect.w) {
                if let Some(cell) = covered.get_mut((row * rect.w + c) as usize) {
                    *cell = true;
                }
            }
        }
        let size = |v: &Value| v.as_u64().unwrap_or(0).min(1000) as u16;
        grid.surfaces.push(Surface {
            key,
            rect,
            cell: (size(&s["cell"][0]), size(&s["cell"][1])),
            under: s["under"].as_bool().unwrap_or(false),
            covered,
            ops,
            open: false,
            offset: (number(&s["offset"][0]), number(&s["offset"][1])),
            whole: (number(&s["whole"][0]), number(&s["whole"][1])),
        });
    }
    let cursor = &payload["cursor"];
    Ok(match (cursor[0].as_u64(), cursor[1].as_u64()) {
        (Some(x), Some(y)) => Some((x as u16, y as u16)),
        _ => None,
    })
}

/// A frontend at the other end of a connection.
pub(crate) struct RemoteFrontend {
    client: ClientId,
    clients: Clients,
    /// What that side shows now, to send only what changed.
    shown: Option<Grid>,
    cursor: Option<(u16, u16)>,
}

impl RemoteFrontend {
    pub(crate) fn new(client: ClientId, clients: Clients) -> Self {
        Self {
            client,
            clients,
            shown: None,
            cursor: None,
        }
    }
}

impl Frontend for RemoteFrontend {
    fn present(&mut self, grid: &Grid, cursor: Option<(u16, u16)>) -> Result<()> {
        let same_size = self
            .shown
            .as_ref()
            .is_some_and(|s| (s.width, s.height) == (grid.width, grid.height));
        let shown = self.shown.as_ref().filter(|_| same_size);
        let runs = runs(grid, shown);
        let same_mouse = shown.is_some_and(|s| s.mouse_off == grid.mouse_off);
        let same_surfaces = self.shown.as_ref().is_some_and(|s| s.surfaces == grid.surfaces);
        if runs.is_empty() && same_size && same_mouse && same_surfaces && cursor == self.cursor {
            return Ok(());
        }
        let surfaces: Vec<Value> = grid
            .surfaces
            .iter()
            .map(|s| {
                let mut out = json!({
                    "key": s.key, "x": s.rect.x, "y": s.rect.y, "w": s.rect.w, "h": s.rect.h,
                    "cell": [s.cell.0, s.cell.1], "under": s.under, "covered": s.covered_runs(),
                });
                let sent = self.shown.as_ref().and_then(|shown| shown.surfaces.iter().find(|b| b.key == s.key));
                if s.whole != (0, 0) {
                    out["offset"] = json!([s.offset.0, s.offset.1]);
                    out["whole"] = json!([s.whole.0, s.whole.1]);
                }
                if sent.is_none_or(|sent| sent.ops != s.ops) {
                    out["ops"] = (*s.ops).clone();
                }
                out
            })
            .collect();
        let payload = json!({
            "w": grid.width, "h": grid.height, "full": !same_size,
            "cursor": cursor.map(|(x, y)| json!([x, y])), "runs": runs, "mouse": !grid.mouse_off,
            "surfaces": surfaces,
        });
        if !self.clients.push(self.client, "ui.grid", &payload) {
            bail!("connection {} is gone", self.client);
        }
        grid.copy_shown(&mut self.shown);
        self.cursor = cursor;
        Ok(())
    }

    /// The next screen goes whole (`"full": true`): the terminal on the
    /// other side writes each cell again.
    fn repaint(&mut self) {
        self.shown = None;
    }
}

/// What a remote terminal sends with `ui.input`, as the kernel takes input:
/// `{"key": "a"}`, `{"paste": "text"}`, `{"resize": [w, h]}`, or
/// `{"mouse": {"kind": "down", "button": "left", "x": 3, "y": 4, "mods": "C"}}`
/// (with `"px"` and `"py"`, where the pointer is in pixels, when the
/// terminal reports that), `{"cell": [w, h]}`, a cell's new size in pixels,
/// or `{"focus": true}`, the terminal got the focus (false: lost it).
pub fn input_of(value: &Value) -> Option<InputEvent> {
    if let Some(key) = value["key"].as_str() {
        return Some(InputEvent::Key(key.to_string()));
    }
    if let Some(text) = value["paste"].as_str() {
        return Some(InputEvent::Paste(text.to_string()));
    }
    if let (Some(width), Some(height)) = (value["resize"][0].as_u64(), value["resize"][1].as_u64())
    {
        return Some(InputEvent::Resize(
            width.clamp(1, MAX_CELLS as u64) as u16,
            height.clamp(1, MAX_CELLS as u64) as u16,
        ));
    }
    if let Some(on) = value["focus"].as_bool() {
        return Some(InputEvent::Focus(on));
    }
    if let (Some(width), Some(height)) = (value["cell"][0].as_u64(), value["cell"][1].as_u64()) {
        return Some(InputEvent::CellSize(width.min(1000) as u16, height.min(1000) as u16));
    }
    let mouse = value.get("mouse")?;
    let pixel = |v: &Value| v.as_u64().map(|n| n.min(u16::MAX as u64) as u16);
    Some(InputEvent::Mouse {
        kind: mouse["kind"].as_str()?.to_string(),
        button: mouse["button"].as_str().unwrap_or("").to_string(),
        x: mouse["x"].as_u64()?.min(u16::MAX as u64) as u16,
        y: mouse["y"].as_u64()?.min(u16::MAX as u64) as u16,
        mods: mouse["mods"].as_str().unwrap_or("").to_string(),
        pixel: pixel(&mouse["px"]).zip(pixel(&mouse["py"])),
    })
}

/// The other direction, for the program at the far end to send.
pub fn input_json(event: &InputEvent) -> Value {
    match event {
        InputEvent::Key(key) => json!({ "key": key }),
        InputEvent::Paste(text) => json!({ "paste": text }),
        InputEvent::Resize(width, height) => json!({ "resize": [width, height] }),
        InputEvent::CellSize(width, height) => json!({ "cell": [width, height] }),
        InputEvent::Focus(on) => json!({ "focus": on }),
        InputEvent::Mouse {
            kind,
            button,
            x,
            y,
            mods,
            pixel,
        } => {
            let mut mouse = json!({ "kind": kind, "button": button, "x": x, "y": y, "mods": mods });
            if let Some((px, py)) = pixel {
                mouse["px"] = json!(px);
                mouse["py"] = json!(py);
            }
            json!({ "mouse": mouse })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::{BOLD, Rect};

    fn painted() -> Grid {
        let mut grid = Grid::new(12, 3);
        let clip = grid.rect();
        let plain = Style::default();
        let loud = Style {
            fg: Some(Color::Rgb(255, 128, 0)),
            bg: Some(Color::Indexed(4)),
            on: BOLD,
            off: 0,
        };
        grid.text(clip, 0, 0, "parts", plain);
        grid.text(clip, 2, 1, "音楽 ok", loud);
        grid.fill(
            clip,
            Rect {
                x: 0,
                y: 2,
                w: 12,
                h: 1,
            },
            Some('─'),
            loud,
        );
        grid
    }

    #[test]
    fn a_screen_sent_whole_is_the_same_screen_at_the_other_end() {
        let grid = painted();
        let payload = json!({ "w": 12, "h": 3, "full": true, "cursor": [3, 1], "runs": runs(&grid, None) });
        let mut far = Grid::new(1, 1);
        let cursor = apply(&mut far, &payload).unwrap();
        assert_eq!(cursor, Some((3, 1)));
        assert_eq!(far.cells, grid.cells, "every cell, wide characters included");
    }

    #[test]
    fn only_what_changed_is_sent_and_it_lands_where_it_belongs() {
        let before = painted();
        let mut after = before.clone();
        let clip = after.rect();
        after.text(clip, 3, 0, "X", Style::default());
        after.text(clip, 4, 1, "楽", Style { fg: Some(Color::Default), ..Style::default() });
        let changed = runs(&after, Some(&before));
        assert_eq!(changed.len(), 2, "two stretches changed: {changed:?}");
        assert_eq!(changed[0][2], "X");
        let mut far = before;
        apply(&mut far, &json!({ "w": 12, "h": 3, "runs": changed })).unwrap();
        assert_eq!(far.cells, after.cells);
        assert!(runs(&after, Some(&after)).is_empty(), "nothing changed, nothing sent");
    }

    #[test]
    fn a_surface_arrives_with_what_covers_it_and_keeps_its_drawing_when_none_is_sent() {
        let mut near = Grid::new(12, 3);
        let index = near.surface("notation#1", Rect { x: 2, y: 0, w: 6, h: 3 }, (10, 20), false).unwrap();
        near.surfaces[index].ops = Arc::new(json!([["r", 0, 0, 5, 5, "#ffffff", "", 1, 0]]));
        // The same view in a second window, a strip under its text.
        let index = near.surface("notation#2", Rect { x: 9, y: 0, w: 3, h: 3 }, (10, 20), true).unwrap();
        near.surfaces[index].ops = Arc::new(json!([["r", 0, 0, 9, 9, "#000000", "", 1, 0]]));
        near.seal_surfaces();
        // A menu over two cells of its middle row.
        let clip = near.rect();
        near.text(clip, 4, 1, "ok", Style::default());
        let s = &near.surfaces[0];
        assert_eq!(s.covered_runs(), vec![[2, 1, 2]]);
        let sent = |with_ops: bool| {
            let surfaces: Vec<Value> = near
                .surfaces
                .iter()
                .map(|s| {
                    let mut surface = json!({
                        "key": s.key, "x": s.rect.x, "y": s.rect.y, "w": s.rect.w, "h": s.rect.h,
                        "cell": [10, 20], "under": s.under, "covered": s.covered_runs(),
                    });
                    if with_ops {
                        surface["ops"] = (*s.ops).clone();
                    }
                    surface
                })
                .collect();
            json!({ "w": 12, "h": 3, "runs": [], "surfaces": surfaces })
        };
        let mut far = Grid::new(12, 3);
        apply(&mut far, &sent(true)).unwrap();
        assert_eq!(far.surfaces, near.surfaces);
        assert!(far.surfaces[1].under, "placed under the text there too");
        apply(&mut far, &sent(false)).unwrap();
        assert_eq!(far.surfaces[0].ops, near.surfaces[0].ops, "the drawing it had");
        assert_eq!(far.surfaces[1].ops, near.surfaces[1].ops, "each by its key");
        apply(&mut far, &json!({ "w": 12, "h": 3, "runs": [] })).unwrap();
        assert!(far.surfaces.is_empty(), "gone when not sent");
    }

    // Found while writing the fuzz target `remote`: a size of
    // billions of cells, or sums past the largest i32, panicked or ran out
    // of memory.
    #[test]
    fn a_surface_with_numbers_out_of_range_is_kept_within_the_screen() {
        let big = i64::from(i32::MAX);
        let surface = json!({
            "key": "far", "x": big, "y": -big, "w": big, "h": big,
            "covered": [[big, 0, big], [0, big, 1], [-5, 1, big]],
        });
        let mut far = Grid::new(12, 3);
        apply(&mut far, &json!({ "w": 12, "h": 3, "surfaces": [surface] })).unwrap();
        let s = &far.surfaces[0];
        assert_eq!(s.rect, Rect { x: 1000, y: -1000, w: 1000, h: 1000 });
        assert_eq!(s.covered_runs(), vec![[0, 1, 1000]], "the one row in range, cut to the width");
        // A second screen draws text with the surface still there.
        apply(&mut far, &json!({ "w": 12, "h": 3, "runs": [[0, 0, "ok", null, null, 0]] })).unwrap();
    }

    #[test]
    fn the_far_terminal_is_told_whether_to_report_the_pointer() {
        let mut far = painted();
        apply(&mut far, &json!({ "w": 12, "h": 3, "runs": [], "mouse": false })).unwrap();
        assert!(far.mouse_off, "the terminal keeps the pointer for its selection");
        apply(&mut far, &json!({ "w": 12, "h": 3, "runs": [] })).unwrap();
        assert!(!far.mouse_off, "without a word it reports the pointer");
    }

    #[test]
    fn input_survives_the_trip() {
        for event in [
            InputEvent::Key("<C-s>".into()),
            InputEvent::Paste("two\nlines".into()),
            InputEvent::Resize(100, 30),
            InputEvent::Mouse {
                kind: "drag".into(),
                button: "left".into(),
                x: 7,
                y: 9,
                mods: "CS".into(),
                pixel: None,
            },
            InputEvent::Mouse {
                kind: "move".into(),
                button: "".into(),
                x: 7,
                y: 9,
                mods: "".into(),
                pixel: Some((75, 190)),
            },
            InputEvent::CellSize(10, 21),
            InputEvent::Focus(true),
        ] {
            let back = input_of(&input_json(&event)).unwrap();
            assert_eq!(format!("{back:?}"), format!("{event:?}"));
        }
        assert!(input_of(&json!({ "nonsense": 1 })).is_none());
    }
}
