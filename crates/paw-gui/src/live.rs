//! Frames made from the live values alone. While the song plays and
//! nothing else happens (no input, no new scene, no change of mode), only
//! what the live values move changes on the screen: the playhead, the
//! meters, the clock. Such a frame does not run egui's pass: the window
//! keeps the shapes of the last pass (crate::damage) and paints again only
//! its live parts, with the values of now, in their places in that list
//! (crate::runner). A pass laid the parts out: each is between two markers
//! (a `Shape::Noop` with a clip rectangle no real shape has), and says what
//! to paint again and where.

use egui::epaint::ClippedShape;
use egui::{Id, LayerId, Painter, Pos2, Rect, Shape, pos2};
use serde_json::Value;

use crate::app::View;

/// The left edge of a marker's clip rectangle: far off any screen.
const MARK_X: f32 = -1.0e7;

/// The values of the state that only move with the song: a state that
/// differs from the last in these alone needs no pass.
pub const LIVE_KEYS: &[&str] = &["position", "time", "clock", "cpu", "levels", "inputs"];

/// The most frames made from the live values in a row: then a pass runs,
/// so that egui's caches of laid out text are let go of now and then.
pub const MOST_IN_A_ROW: u32 = 30;

/// What a live part paints, and where.
#[derive(Clone, Debug)]
pub enum Part {
    /// The role `index` of the scene of the window `win`, drawn from `from`
    /// on cells `cell` big; `under`, whether the pointer was over it.
    Role { win: String, index: usize, from: Pos2, cell: (f32, f32), under: bool },
    /// The transport's clock: bars and beats, minutes and seconds.
    Clock { rect: Rect },
    /// The bar of the engine's load.
    Load { rect: Rect },
}

/// The live parts of the last pass, each with its layer and its cut, in
/// the order of their markers.
#[derive(Default)]
pub struct Parts {
    pub list: Vec<(LayerId, Rect, Part)>,
}

impl Parts {
    /// Start a live part painted with `painter`: what it paints next, up to
    /// `end`, is the part. Returns its number.
    pub fn begin(&mut self, painter: &Painter, part: Part) -> u32 {
        let n = self.list.len() as u32;
        self.list.push((painter.layer_id(), painter.clip_rect(), part));
        painter.ctx().graphics_mut(|g| g.entry(painter.layer_id()).add(marker_rect(n, false), Shape::Noop));
        n
    }

    /// The part `n` is painted.
    pub fn end(&mut self, painter: &Painter, n: u32) {
        painter.ctx().graphics_mut(|g| g.entry(painter.layer_id()).add(marker_rect(n, true), Shape::Noop));
    }
}

fn marker_rect(n: u32, end: bool) -> Rect {
    Rect::from_min_max(pos2(MARK_X, n as f32), pos2(MARK_X + if end { 1.0 } else { 0.0 }, n as f32))
}

/// The part a shape marks the start (false) or the end (true) of.
pub fn marker(shape: &ClippedShape) -> Option<(u32, bool)> {
    if !matches!(shape.shape, Shape::Noop) || shape.clip_rect.min.x != MARK_X {
        return None;
    }
    Some((shape.clip_rect.min.y as u32, shape.clip_rect.max.x != MARK_X))
}

/// The shapes of the parts, each between its markers, in a frame's list:
/// `(part, first, end)`, the shapes being `first..end`.
pub fn ranges(shapes: &[ClippedShape]) -> Vec<(u32, usize, usize)> {
    let mut out = Vec::new();
    let mut open: Option<(u32, usize)> = None;
    for (i, shape) in shapes.iter().enumerate() {
        match (marker(shape), open) {
            (Some((n, false)), _) => open = Some((n, i + 1)),
            (Some((n, true)), Some((m, first))) if n == m => {
                out.push((n, first, i));
                open = None;
            }
            _ => {}
        }
    }
    out
}

/// `shapes` with the shapes of each part in `new` in place of its own.
pub fn splice(shapes: &[ClippedShape], new: &[(u32, Vec<ClippedShape>)]) -> Vec<ClippedShape> {
    let mut out = Vec::with_capacity(shapes.len());
    let mut skipping = false;
    for shape in shapes {
        match marker(shape) {
            Some((n, false)) => {
                out.push(shape.clone());
                if let Some((_, part)) = new.iter().find(|(m, _)| *m == n) {
                    out.extend(part.iter().cloned());
                    skipping = true;
                }
            }
            Some((_, true)) => {
                skipping = false;
                out.push(shape.clone());
            }
            None if !skipping => out.push(shape.clone()),
            None => {}
        }
    }
    out
}

/// Whether a state differs from `before` in the live values alone.
pub fn only_live(state: &Value, before: &Value) -> bool {
    let (Some(new), Some(old)) = (state.as_object(), before.as_object()) else { return false };
    let counted = |o: &serde_json::Map<String, Value>| o.keys().filter(|k| !LIVE_KEYS.contains(&k.as_str())).count();
    counted(new) == counted(old) && new.iter().all(|(k, v)| LIVE_KEYS.contains(&k.as_str()) || old.get(k) == Some(v))
}

impl View {
    /// The live parts of the last pass painted again with the values of
    /// now, if nothing but those values changed since it: no input (`raw`),
    /// no new scene, no new state but live values, no other window open.
    /// None when a pass must run; the state taken is kept for it.
    pub fn replay(&mut self, ctx: &egui::Context, raw: &egui::RawInput) -> Option<Vec<(u32, Vec<ClippedShape>)>> {
        let quiet = raw.events.is_empty() && raw.hovered_files.is_empty() && raw.dropped_files.is_empty();
        if !quiet || !self.canvases.is_empty() || self.portal.busy || self.gone || self.s.tick.is_null() {
            return None;
        }
        // What the kernel sent: anything but the live values needs a pass.
        let polled = self.k.borrow_mut().state();
        let state = match polled {
            Ok(state) => state,
            Err(err) => {
                self.gone = true;
                self.show(&format!("{err:#}"), true);
                return None;
            }
        };
        let patches = self.k.borrow_mut().patches();
        let live = self.k.borrow_mut().live();
        if let Some(live) = live {
            self.scenes.live = live;
        }
        if !patches.is_empty() {
            self.take_patches(patches);
            if let Some(state) = state {
                self.take(state);
            }
            return None;
        }
        if let Some(state) = state {
            if state.get("project").is_some() || !only_live(&state, &self.s.tick) {
                self.take(state);
                return None;
            }
            self.s.tick = state;
        }
        let filled = ctx.fonts(|f| f.font_atlas_fill_ratio());
        let mut out: Vec<(u32, Vec<ClippedShape>)> = Vec::with_capacity(self.live.list.len());
        for (n, (layer, clip, part)) in self.live.list.iter().enumerate() {
            let kept = LayerId::new(layer.order, Id::unique("paw-live-part"));
            let painter = Painter::new(ctx.clone(), kept, *clip);
            match part {
                Part::Role { win, index, from, cell, under } => {
                    if let Some(shown) = self.scenes.shown_of(win) {
                        shown.role_live(&painter, *index, *from, *cell, &self.scenes.live, *under);
                    }
                }
                Part::Clock { rect } => self.clock(&painter, *rect),
                Part::Load { rect } => self.load(&painter, *rect),
            }
            let list = ctx.graphics_mut(|g| std::mem::take(g.entry(kept)));
            out.push((n as u32, list.all_entries().cloned().collect()));
        }
        // The font's atlas made room for more glyphs: a pass sends it.
        if ctx.fonts(|f| f.font_atlas_fill_ratio()) != filled {
            return None;
        }
        Some(out)
    }
}

/// How far into the font's atlas the glyphs of the last pass reach. The
/// atlas places each glyph it rasterizes after the last, row by row; a pass
/// sends the pixels of those it placed to the graphics card. A glyph of a
/// frame made from the live values that lies further on (a digit the clock
/// shows for the first time, at a new fraction of a pixel) has no pixels
/// there yet: a pass makes that frame instead.
#[derive(Default)]
pub struct Glyphs {
    /// The furthest glyph, as its row and column in the atlas.
    reach: (u16, u16),
}

/// Each glyph of a shape, as where it starts in the font's atlas: its row
/// and column.
fn each_glyph(shape: &Shape, f: &mut impl FnMut((u16, u16))) {
    match shape {
        Shape::Text(text) => {
            for row in &text.galley.rows {
                for glyph in &row.row.glyphs {
                    if !glyph.uv_rect.is_nothing() {
                        f((glyph.uv_rect.min[1], glyph.uv_rect.min[0]));
                    }
                }
            }
        }
        Shape::Vec(shapes) => shapes.iter().for_each(|s| each_glyph(s, f)),
        _ => {}
    }
}

impl Glyphs {
    /// The glyphs of a pass's shapes.
    pub fn learn(&mut self, shapes: &[ClippedShape]) {
        let mut reach = (0, 0);
        for shape in shapes {
            each_glyph(&shape.shape, &mut |at| reach = reach.max(at));
        }
        self.reach = reach;
    }

    /// Whether every glyph of the parts has its pixels on the card.
    pub fn know(&self, parts: &[(u32, Vec<ClippedShape>)]) -> bool {
        let mut all = true;
        for shape in parts.iter().flat_map(|(_, s)| s) {
            each_glyph(&shape.shape, &mut |at| all &= at <= self.reach);
        }
        all
    }
}
