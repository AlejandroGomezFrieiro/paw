//! A view's drawing (the operations `paw.canvas.paint` returns) made into
//! pixels, the same in the terminal and in the window.
//!
//! The operations, positions in pixels of the drawing:
//!
//!   { "r", x, y, w, h, fill, stroke, stroke width, radius }
//!   { "t", x, y, text, colour, size, bold (0 or 1), align, width }
//!   { "p", path commands, stroke, stroke width, fill }
//!   { "m", x, y, w, h, text, colour, background, attributes }
//!   { "g", x, y, size, code point, colour, font }
//!   { "i", x, y, w, h, key, sx, sy, sw, sh }
//!   { "cut", x, top, bottom }
//!   { "layer", name }
//!
//! `g` is a glyph of a SMuFL music font (Leland unless `font` names
//! Bravura or Petaluma) with its origin at `x, y` and `size` pixels to the
//! em (four staff spaces). `i` is a picture of pixels kept under `key`
//! ([`pixels`]), its part `sx, sy, sw, sh` (in fractions of it: 0, 0, 1, 1
//! for all of it) stretched over `x, y, w, h`; a picture not kept is left
//! out. `cut` marks where the drawing may be cut into
//! pieces, a barline, between `top` and `bottom` (the whole height without
//! them); it draws nothing. What follows `layer` belongs to that layer
//! until the next: everything before the first, and the layer `base`, is
//! the page; any other layer is drawn over it, and a terminal that layers
//! images well shows it as an image of its own above the page, so that it
//! moves without the page being sent again.
//!
//! Colours are `#rrggbb` or `#rrggbbaa`; an empty string is none.
//!
//! `vector` writes a drawing as SVG or PDF instead of pixels (without its
//! pictures of pixels).

pub mod fonts;
pub mod kitty;
pub mod pixels;
pub mod probe;
pub mod tiles;
pub mod vector;

use std::hash::{Hash, Hasher};
use std::sync::Arc;

use serde_json::Value;
use tiny_skia::{
    Color, FillRule, FilterQuality, LineCap, LineJoin, Paint, Path, PathBuilder, Pattern, Pixmap, Rect, SpreadMode,
    Stroke, Transform,
};

pub use fonts::{Font, glyph_outline, smufl};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgba(pub u8, pub u8, pub u8, pub u8);

impl Rgba {
    /// `#rrggbb` or `#rrggbbaa`; nothing for anything else.
    pub fn parse(value: &Value) -> Option<Rgba> {
        let text = value.as_str()?;
        if !text.starts_with('#') {
            return None;
        }
        let c: paw_scene::color::Rgba = text.parse().ok()?;
        Some(Rgba(c.r, c.g, c.b, c.a))
    }

    fn paint(self) -> Paint<'static> {
        let mut paint = Paint::default();
        paint.set_color(Color::from_rgba8(self.0, self.1, self.2, self.3));
        paint.anti_alias = true;
        paint
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Align {
    Left,
    Center,
    Right,
}

#[derive(Clone, Debug)]
pub enum Op {
    Rect {
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        fill: Option<Rgba>,
        stroke: Option<Rgba>,
        width: f32,
        radius: f32,
    },
    Text {
        x: f32,
        y: f32,
        text: String,
        colour: Rgba,
        size: f32,
        bold: bool,
        align: Align,
        width: f32,
    },
    Path {
        path: Path,
        stroke: Option<Rgba>,
        width: f32,
        fill: Option<Rgba>,
    },
    Mono {
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        text: String,
        colour: Rgba,
        background: Option<Rgba>,
        attrs: u32,
    },
    Glyph {
        x: f32,
        y: f32,
        size: f32,
        codepoint: char,
        colour: Rgba,
        font: Font,
    },
    /// A picture of pixels: the part `src` of it (fractions of its width
    /// and height: x, y, w, h) over the rectangle `x, y, w, h`.
    Image {
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        src: [f32; 4],
        pixmap: Arc<Pixmap>,
    },
}

/// A place the drawing may be cut at: `x`, between `top` and `bottom`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Cut {
    pub x: f32,
    pub top: f32,
    pub bottom: f32,
}

/// An operation with the box it draws in (left, top, right, bottom) and a
/// hash of what it is: a piece of the drawing is painted again only when
/// an operation reaching into it changed.
#[derive(Clone, Debug)]
pub struct Item {
    pub op: Op,
    pub bounds: [f32; 4],
    pub key: u64,
}

/// Which of a drawing's layers to paint.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Layers {
    Page,
    Overlay,
    Both,
}

/// A drawing ready to paint: its operations by layer, the page first.
#[derive(Clone, Debug, Default)]
pub struct Drawing {
    pub page: Vec<Item>,
    /// What is drawn over the page, in order.
    pub overlay: Vec<Item>,
    pub cuts: Vec<Cut>,
}

fn number(value: &Value) -> f32 {
    value.as_f64().unwrap_or(0.0) as f32
}

fn text(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        _ => String::new(),
    }
}

impl Drawing {
    /// The operations of a drawing as JSON (a list of lists); what is not
    /// understood is passed over.
    pub fn parse(ops: &Value) -> Drawing {
        let mut drawing = Drawing::default();
        let mut over = false;
        for op in ops.as_array().into_iter().flatten() {
            let Some(kind) = op[0].as_str() else { continue };
            let parsed = match kind {
                "r" => Some(Op::Rect {
                    x: number(&op[1]),
                    y: number(&op[2]),
                    w: number(&op[3]),
                    h: number(&op[4]),
                    fill: Rgba::parse(&op[5]),
                    stroke: Rgba::parse(&op[6]),
                    width: if op[7].is_null() { 1.0 } else { number(&op[7]) },
                    radius: number(&op[8]),
                }),
                "t" => Some(Op::Text {
                    x: number(&op[1]),
                    y: number(&op[2]),
                    text: text(&op[3]),
                    colour: Rgba::parse(&op[4]).unwrap_or(Rgba(255, 255, 255, 255)),
                    size: if op[5].is_null() { 12.0 } else { number(&op[5]) },
                    bold: number(&op[6]) > 0.5,
                    align: match op[7].as_str() {
                        Some("center") => Align::Center,
                        Some("right") => Align::Right,
                        _ => Align::Left,
                    },
                    width: if op[8].is_null() { f32::MAX } else { number(&op[8]) },
                }),
                "p" => path_of(op[1].as_str().unwrap_or("")).map(|path| Op::Path {
                    path,
                    stroke: Rgba::parse(&op[2]),
                    width: if op[3].is_null() { 1.0 } else { number(&op[3]) },
                    fill: Rgba::parse(&op[4]),
                }),
                "m" => Some(Op::Mono {
                    x: number(&op[1]),
                    y: number(&op[2]),
                    w: number(&op[3]),
                    h: number(&op[4]),
                    text: text(&op[5]),
                    colour: Rgba::parse(&op[6]).unwrap_or(Rgba(255, 255, 255, 255)),
                    background: Rgba::parse(&op[7]),
                    attrs: number(&op[8]) as u32,
                }),
                "g" => {
                    let codepoint = op[4]
                        .as_u64()
                        .and_then(|c| char::from_u32(c as u32))
                        .or_else(|| op[4].as_str().and_then(|s| s.chars().next()));
                    match (codepoint, Font::music(op[6].as_str())) {
                        (Some(codepoint), Some(font)) => Some(Op::Glyph {
                            x: number(&op[1]),
                            y: number(&op[2]),
                            size: number(&op[3]),
                            codepoint,
                            colour: Rgba::parse(&op[5]).unwrap_or(Rgba(255, 255, 255, 255)),
                            font,
                        }),
                        _ => None,
                    }
                }
                "i" => op[5].as_str().and_then(pixels::get).map(|pixmap| {
                    let part = |i: usize, or: f32| if op[i].is_null() { or } else { number(&op[i]) };
                    Op::Image {
                        x: number(&op[1]),
                        y: number(&op[2]),
                        w: number(&op[3]),
                        h: number(&op[4]),
                        src: [part(6, 0.0), part(7, 0.0), part(8, 1.0), part(9, 1.0)],
                        pixmap,
                    }
                }),
                "cut" => {
                    drawing.cuts.push(Cut {
                        x: number(&op[1]),
                        top: op[2].as_f64().map_or(f32::MIN, |v| v as f32),
                        bottom: op[3].as_f64().map_or(f32::MAX, |v| v as f32),
                    });
                    None
                }
                "layer" => {
                    over = !matches!(op[1].as_str(), Some("base") | None);
                    None
                }
                _ => None,
            };
            if let Some(parsed) = parsed {
                let item = Item {
                    bounds: bounds(&parsed),
                    key: {
                        let mut hasher = std::hash::DefaultHasher::new();
                        op.to_string().hash(&mut hasher);
                        hasher.finish()
                    },
                    op: parsed,
                };
                if over {
                    drawing.overlay.push(item);
                } else {
                    drawing.page.push(item);
                }
            }
        }
        drawing
    }

    /// The page alone, on a transparent pixmap of the given size.
    pub fn paint_page(&self, width: u32, height: u32) -> Option<Pixmap> {
        let mut pixmap = Pixmap::new(width.max(1), height.max(1))?;
        paint(&mut pixmap, &self.page, 0.0, 0.0);
        Some(pixmap)
    }

    /// Page and overlay together, `scale` pixels to a pixel of the drawing.
    pub fn paint_scaled(&self, width: u32, height: u32, scale: f32) -> Option<Pixmap> {
        let mut pixmap = Pixmap::new(width.max(1), height.max(1))?;
        let at = Transform::from_scale(scale, scale);
        paint_with(&mut pixmap, &self.page, at);
        paint_with(&mut pixmap, &self.overlay, at);
        Some(pixmap)
    }

    /// Page and overlay together.
    pub fn paint_all(&self, width: u32, height: u32) -> Option<Pixmap> {
        let mut pixmap = self.paint_page(width, height)?;
        paint(&mut pixmap, &self.overlay, 0.0, 0.0);
        Some(pixmap)
    }

    /// The operations of some layers that reach into a rectangle `[x, y, w, h]`.
    fn within(&self, area: [f32; 4], layers: Layers) -> impl Iterator<Item = &Item> {
        let [x, y, w, h] = area;
        let page = if layers == Layers::Overlay { &[] } else { &self.page[..] };
        let over = if layers == Layers::Page { &[] } else { &self.overlay[..] };
        page.iter().chain(over).filter(move |item| {
            let [l, t, r, b] = item.bounds;
            l < x + w && r > x && t < y + h && b > y
        })
    }

    /// What a piece of the drawing `[x, y, w, h]` shows, as a hash of the
    /// operations that reach into it: the same hash, the same pixels.
    pub fn piece_key(&self, area: [f32; 4], layers: Layers) -> u64 {
        let mut hasher = std::hash::DefaultHasher::new();
        area.map(f32::to_bits).hash(&mut hasher);
        (layers as u8).hash(&mut hasher);
        for item in self.within(area, layers) {
            item.key.hash(&mut hasher);
        }
        hasher.finish()
    }

    /// A piece of the drawing `[x, y, w, h]` (whole pixels) on a pixmap of
    /// its own: only the operations that reach into it are drawn, so a
    /// small piece of a large page is quick.
    pub fn paint_piece(&self, area: [f32; 4], layers: Layers) -> Option<Pixmap> {
        let mut pixmap = Pixmap::new(area[2].max(1.0) as u32, area[3].max(1.0) as u32)?;
        let items: Vec<Item> = self.within(area, layers).cloned().collect();
        paint(&mut pixmap, &items, area[0], area[1]);
        Some(pixmap)
    }

    /// The box the overlay draws in, in whole pixels `[x, y, w, h]`, or
    /// nothing when it draws nothing.
    pub fn overlay_box(&self) -> Option<[f32; 4]> {
        let mut out: Option<[f32; 4]> = None;
        for item in &self.overlay {
            let [l, t, r, b] = item.bounds;
            out = Some(match out {
                None => [l, t, r, b],
                Some([l0, t0, r0, b0]) => [l0.min(l), t0.min(t), r0.max(r), b0.max(b)],
            });
        }
        out.map(|[l, t, r, b]| {
            let (l, t) = (l.floor().max(0.0), t.floor().max(0.0));
            [l, t, r.ceil() - l, b.ceil() - t]
        })
        .filter(|a| a[2] > 0.0 && a[3] > 0.0)
    }
}

/// The box an operation draws in, generously: left, top, right, bottom.
fn bounds(op: &Op) -> [f32; 4] {
    match op {
        Op::Rect { x, y, w, h, width, stroke, .. } => {
            let pad = if stroke.is_some() { *width } else { 0.0 };
            [x - pad, y - pad, x + w + pad, y + h + pad]
        }
        Op::Text { x, y, text, size, bold, align, width, .. } => {
            let font = if *bold { Font::SansBold } else { Font::Sans };
            let run = measure(font, text, *size).min(*width);
            let left = match align {
                Align::Left => *x,
                Align::Center => x - run / 2.0,
                Align::Right => x - run,
            };
            [left - 1.0, y - 1.0, left + run + 1.0, y + size * 1.5]
        }
        Op::Path { path, width, stroke, .. } => {
            let b = path.bounds();
            let pad = if stroke.is_some() { width + 1.0 } else { 1.0 };
            [b.left() - pad, b.top() - pad, b.right() + pad, b.bottom() + pad]
        }
        Op::Mono { x, y, w, h, .. } => [*x, *y, x + w + 2.0, y + h],
        Op::Image { x, y, w, h, .. } => [*x, *y, x + w, y + h],
        Op::Glyph { x, y, size, codepoint, font, .. } => {
            match font.face().glyph_index(*codepoint).and_then(|g| font.outline(g)) {
                Some(path) => {
                    let b = path.bounds();
                    [x + b.left() * size - 1.0, y + b.top() * size - 1.0, x + b.right() * size + 1.0, y + b.bottom() * size + 1.0]
                }
                None => [*x, *y, *x, *y],
            }
        }
    }
}

/// Draw items onto a pixmap whose corner is at `(dx, dy)` of the drawing.
pub fn paint(pixmap: &mut Pixmap, items: &[Item], dx: f32, dy: f32) {
    paint_with(pixmap, items, Transform::from_translate(-dx, -dy));
}

/// Draw items onto a pixmap through a transform: `scale` for a screen with
/// more pixels than the drawing's (a window on a HiDPI screen).
pub fn paint_with(pixmap: &mut Pixmap, items: &[Item], shift: Transform) {
    for item in items {
        match &item.op {
            Op::Rect { x, y, w, h, fill, stroke, width, radius } => {
                rect(pixmap, shift, *x, *y, *w, *h, *fill, *stroke, *width, *radius)
            }
            Op::Text { x, y, text, colour, size, bold, align, width } => {
                let font = if *bold { Font::SansBold } else { Font::Sans };
                let run = measure(font, text, *size);
                let left = match align {
                    Align::Left => *x,
                    Align::Center => x - run.min(*width) / 2.0,
                    Align::Right => x - run.min(*width),
                };
                // A line's top is at `y`, as the window draws text: the baseline is an ascent below.
                let baseline = y + font.ascent() * size;
                draw_text(pixmap, shift, font, text, left, baseline, *size, *colour, left + width);
            }
            Op::Path { path, stroke, width, fill } => {
                if let Some(fill) = fill {
                    pixmap.fill_path(path, &fill.paint(), FillRule::Winding, shift, None);
                }
                if let Some(stroke) = stroke {
                    let style = Stroke {
                        width: *width,
                        line_cap: LineCap::Butt,
                        line_join: LineJoin::Miter,
                        ..Stroke::default()
                    };
                    pixmap.stroke_path(path, &stroke.paint(), &style, shift, None);
                }
            }
            Op::Mono { x, y, w, h, text, colour, background, attrs } => {
                if let Some(background) = background {
                    rect(pixmap, shift, *x, *y, *w, *h, Some(*background), None, 1.0, 0.0);
                }
                let font = if attrs & 1 != 0 { Font::MonoBold } else { Font::Mono };
                let size = h / font.line_height();
                let baseline = y + (h - font.line_height() * size) / 2.0 + font.ascent() * size;
                draw_text(pixmap, shift, font, text, *x, baseline, size, *colour, x + w);
                if attrs & 8 != 0 {
                    rect(pixmap, shift, *x, y + h - 2.0, *w, 1.0, Some(*colour), None, 1.0, 0.0);
                }
                if attrs & 32 != 0 {
                    rect(pixmap, shift, *x, y + h / 2.0, *w, 1.0, Some(*colour), None, 1.0, 0.0);
                }
            }
            Op::Glyph { x, y, size, codepoint, colour, font } => {
                if let Some(glyph) = font.face().glyph_index(*codepoint)
                    && let Some(path) = font.outline(glyph)
                {
                    let at = Transform::from_row(*size, 0.0, 0.0, *size, *x, *y).post_concat(shift);
                    pixmap.fill_path(&path, &colour.paint(), FillRule::Winding, at, None);
                }
            }
            Op::Image { x, y, w, h, src, pixmap: picture } => image(pixmap, shift, [*x, *y, *w, *h], *src, picture),
        }
    }
}

/// The part `src` of a picture (in fractions of it) stretched over `area`.
fn image(pixmap: &mut Pixmap, shift: Transform, area: [f32; 4], src: [f32; 4], picture: &Pixmap) {
    let [x, y, w, h] = area;
    let Some(rect) = Rect::from_xywh(x, y, w, h) else { return };
    let (pw, ph) = (picture.width() as f32, picture.height() as f32);
    let (sw, sh) = (src[2] * pw, src[3] * ph);
    if sw <= 0.0 || sh <= 0.0 {
        return;
    }
    // From the picture's pixels to the drawing's.
    let (kx, ky) = (w / sw, h / sh);
    let at = Transform::from_row(kx, 0.0, 0.0, ky, x - src[0] * pw * kx, y - src[1] * ph * ky);
    // Made bigger, its pixels show as they are (a spectrogram's bins);
    // made smaller, they are mixed.
    let quality = if kx >= 1.0 && ky >= 1.0 { FilterQuality::Nearest } else { FilterQuality::Bilinear };
    let paint = Paint { shader: Pattern::new(picture.as_ref(), SpreadMode::Pad, quality, 1.0, at), ..Paint::default() };
    pixmap.fill_rect(rect, &paint, shift, None);
}

#[allow(clippy::too_many_arguments)]
fn rect(pixmap: &mut Pixmap, shift: Transform, x: f32, y: f32, w: f32, h: f32, fill: Option<Rgba>, stroke: Option<Rgba>, width: f32, radius: f32) {
    let Some(area) = Rect::from_xywh(x, y, w, h) else { return };
    if let Some(fill) = fill {
        if radius > 0.0 {
            if let Some(path) = rounded(area, radius) {
                pixmap.fill_path(&path, &fill.paint(), FillRule::Winding, shift, None);
            }
        } else {
            pixmap.fill_rect(area, &fill.paint(), shift, None);
        }
    }
    if let Some(stroke) = stroke.filter(|s| s.3 > 0 && width > 0.0) {
        // The border is drawn inside the rectangle, as the window draws it.
        let half = width / 2.0;
        let Some(inner) = Rect::from_xywh(x + half, y + half, w - width, h - width) else { return };
        let path = if radius > 0.0 { rounded(inner, (radius - half).max(0.0)) } else { Some(PathBuilder::from_rect(inner)) };
        if let Some(path) = path {
            let style = Stroke { width, ..Stroke::default() };
            pixmap.stroke_path(&path, &stroke.paint(), &style, shift, None);
        }
    }
}

pub(crate) fn rounded(area: Rect, radius: f32) -> Option<Path> {
    let r = radius.min(area.width() / 2.0).min(area.height() / 2.0);
    // How far along the edge a cubic's handles go to make a quarter circle.
    let k = r * 0.4477;
    let (l, t, rt, b) = (area.left(), area.top(), area.right(), area.bottom());
    let mut p = PathBuilder::new();
    p.move_to(l + r, t);
    p.line_to(rt - r, t);
    p.cubic_to(rt - k, t, rt, t + k, rt, t + r);
    p.line_to(rt, b - r);
    p.cubic_to(rt, b - k, rt - k, b, rt - r, b);
    p.line_to(l + r, b);
    p.cubic_to(l + k, b, l, b - k, l, b - r);
    p.line_to(l, t + r);
    p.cubic_to(l, t + k, l + k, t, l + r, t);
    p.close();
    p.finish()
}

/// How wide a line of text is at a size, in pixels.
pub fn measure(font: Font, text: &str, size: f32) -> f32 {
    let face = font.face();
    text.chars()
        .filter_map(|c| face.glyph_index(c))
        .map(|g| font.advance(g) * size)
        .sum()
}

#[allow(clippy::too_many_arguments)]
fn draw_text(pixmap: &mut Pixmap, shift: Transform, font: Font, text: &str, x: f32, baseline: f32, size: f32, colour: Rgba, right: f32) {
    let face = font.face();
    let paint = colour.paint();
    let mut pen = x;
    for c in text.chars() {
        let Some(glyph) = face.glyph_index(c) else { continue };
        let advance = font.advance(glyph) * size;
        // What does not fit is left out, a whole character at a time.
        if pen + advance > right + 0.5 {
            break;
        }
        if let Some(path) = font.outline(glyph) {
            let at = Transform::from_row(size, 0.0, 0.0, size, pen, baseline).post_concat(shift);
            pixmap.fill_path(&path, &paint, FillRule::Winding, at, None);
        }
        pen += advance;
    }
}

/// Path commands as SVG writes them (`M`, `L`, `H`, `V`, `C`, `Q`, `Z`, and
/// their relative forms), with numbers apart by spaces or commas.
pub fn path_of(commands: &str) -> Option<Path> {
    let mut tokens = Vec::new();
    let mut number = String::new();
    let flush = |number: &mut String, tokens: &mut Vec<Token>| {
        if let Ok(value) = number.parse::<f32>() {
            tokens.push(Token::Number(value));
        }
        number.clear();
    };
    for c in commands.chars() {
        match c {
            'M' | 'm' | 'L' | 'l' | 'H' | 'h' | 'V' | 'v' | 'C' | 'c' | 'Q' | 'q' | 'Z' | 'z' => {
                flush(&mut number, &mut tokens);
                tokens.push(Token::Command(c));
            }
            '-' if !number.is_empty() && !number.ends_with(['e', 'E']) => {
                flush(&mut number, &mut tokens);
                number.push(c);
            }
            ' ' | ',' | '\n' | '\t' => flush(&mut number, &mut tokens),
            _ => number.push(c),
        }
    }
    flush(&mut number, &mut tokens);

    let mut p = PathBuilder::new();
    let (mut cx, mut cy, mut sx, mut sy) = (0.0f32, 0.0f32, 0.0f32, 0.0f32);
    let mut command = 'M';
    let mut i = 0;
    let args = |i: &mut usize, n: usize| -> Option<Vec<f32>> {
        let mut out = Vec::with_capacity(n);
        for _ in 0..n {
            match tokens.get(*i) {
                Some(Token::Number(v)) => out.push(*v),
                _ => return None,
            }
            *i += 1;
        }
        Some(out)
    };
    let len = tokens.len();
    while i < len {
        // A command letter, or more numbers for the one before.
        if let Token::Command(c) = tokens[i] {
            command = c;
            i += 1;
            if c == 'Z' || c == 'z' {
                p.close();
                (cx, cy) = (sx, sy);
                continue;
            }
        }
        let relative = command.is_ascii_lowercase();
        let (ox, oy) = if relative { (cx, cy) } else { (0.0, 0.0) };
        match command.to_ascii_uppercase() {
            'M' => {
                let a = args(&mut i, 2)?;
                (cx, cy) = (a[0] + ox, a[1] + oy);
                (sx, sy) = (cx, cy);
                p.move_to(cx, cy);
                // Pairs after a move are lines.
                command = if relative { 'l' } else { 'L' };
            }
            'L' => {
                let a = args(&mut i, 2)?;
                (cx, cy) = (a[0] + ox, a[1] + oy);
                p.line_to(cx, cy);
            }
            'H' => {
                let a = args(&mut i, 1)?;
                cx = a[0] + ox;
                p.line_to(cx, cy);
            }
            'V' => {
                let a = args(&mut i, 1)?;
                cy = a[0] + oy;
                p.line_to(cx, cy);
            }
            'C' => {
                let a = args(&mut i, 6)?;
                p.cubic_to(a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy, a[4] + ox, a[5] + oy);
                (cx, cy) = (a[4] + ox, a[5] + oy);
            }
            'Q' => {
                let a = args(&mut i, 4)?;
                p.quad_to(a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy);
                (cx, cy) = (a[2] + ox, a[3] + oy);
            }
            _ => return None,
        }
    }
    p.finish()
}

#[derive(Clone, Copy)]
enum Token {
    Command(char),
    Number(f32),
}

/// A pixmap's pixels as straight (not premultiplied) RGBA, as the kitty
/// graphics protocol and an image in the window take them.
pub fn straight_rgba(pixmap: &Pixmap) -> Vec<u8> {
    let mut out = pixmap.data().to_vec();
    for px in out.chunks_exact_mut(4) {
        let a = px[3] as u32;
        if a != 0 && a != 255 {
            for c in &mut px[..3] {
                *c = ((*c as u32 * 255 + a / 2) / a).min(255) as u8;
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn at(pixmap: &Pixmap, x: u32, y: u32) -> (u8, u8, u8, u8) {
        let p = pixmap.pixel(x, y).unwrap().demultiply();
        (p.red(), p.green(), p.blue(), p.alpha())
    }

    #[test]
    fn rectangles_fill_whole_pixels_exactly() {
        let drawing = Drawing::parse(&json!([["r", 2, 3, 4, 1, "#ff0000", "", 1, 0]]));
        let pixmap = drawing.paint_page(10, 10).unwrap();
        assert_eq!(at(&pixmap, 2, 3), (255, 0, 0, 255));
        assert_eq!(at(&pixmap, 5, 3), (255, 0, 0, 255));
        assert_eq!(at(&pixmap, 6, 3).3, 0, "not past its right edge");
        assert_eq!(at(&pixmap, 2, 4).3, 0, "one pixel tall");
        assert_eq!(at(&pixmap, 0, 0).3, 0, "the rest is transparent");
    }

    #[test]
    fn paths_stroke_and_fill_in_svg_commands() {
        let path = path_of("M 1 1 L 9 1 L 9 9 Z").unwrap();
        assert_eq!(path.bounds(), tiny_skia::Rect::from_ltrb(1.0, 1.0, 9.0, 9.0).unwrap());
        let relative = path_of("m1,1 h8 v8 z").unwrap();
        assert_eq!(relative.bounds(), path.bounds());
        let curve = path_of("M0 0C 5 -5 10 5 15 0Q20 5 25-3").unwrap();
        assert!(curve.bounds().right() >= 25.0 && curve.bounds().top() < 0.0);
        let drawing = Drawing::parse(&json!([["p", "M 0 5 L 10 5", "#00ff00", 2, ""], ["p", "M 0 0 L 4 0 L 4 4 L 0 4 Z", "", 1, "#0000ff"]]));
        let pixmap = drawing.paint_page(12, 12).unwrap();
        assert_eq!(at(&pixmap, 5, 5), (0, 255, 0, 255));
        assert_eq!(at(&pixmap, 2, 2), (0, 0, 255, 255));
    }

    #[test]
    fn a_glyph_is_drawn_at_its_origin_from_the_music_font() {
        // A black notehead, 40 px to the em: 10 px a staff space, its origin
        // at the left on the middle of the head.
        let drawing = Drawing::parse(&json!([["g", 10, 20, 40, 0xE0A4, "#ffffff"]]));
        let pixmap = drawing.paint_page(40, 40).unwrap();
        assert_eq!(at(&pixmap, 15, 20), (255, 255, 255, 255), "inside the head");
        assert_eq!(at(&pixmap, 15, 30).3, 0, "a staff space below is clear");
        assert_eq!(at(&pixmap, 5, 20).3, 0, "nothing left of the origin");
        // The same in Bravura is a different shape.
        let other = Drawing::parse(&json!([["g", 10, 20, 40, 0xE050, "#ffffff", "Bravura"]])).paint_page(40, 40).unwrap();
        let leland = Drawing::parse(&json!([["g", 10, 20, 40, 0xE050, "#ffffff"]])).paint_page(40, 40).unwrap();
        assert_ne!(other.data(), leland.data());
    }

    #[test]
    fn text_is_drawn_in_the_window_font_and_cut_at_its_width() {
        let wide = Drawing::parse(&json!([["t", 0, 0, "MMMM", "#ffffff", 14, 0, "left", 1000]])).paint_page(80, 20).unwrap();
        let cut = Drawing::parse(&json!([["t", 0, 0, "MMMM", "#ffffff", 14, 0, "left", 20]])).paint_page(80, 20).unwrap();
        let ink = |p: &Pixmap, from: u32| (from..80).flat_map(|x| (0..20).map(move |y| (x, y))).filter(|&(x, y)| at(p, x, y).3 > 0).count();
        assert!(ink(&wide, 30) > 10, "four letters reach past 30 px");
        assert_eq!(ink(&cut, 22), 0, "cut at 20 px");
        assert!(measure(Font::Sans, "MMMM", 14.0) > 40.0);
    }

    #[test]
    fn layers_after_the_page_are_the_overlay_and_cuts_draw_nothing() {
        let drawing = Drawing::parse(&json!([
            ["r", 0, 0, 2, 2, "#ffffff", "", 1, 0],
            ["cut", 5, 0, 10],
            ["layer", "cursor"],
            ["r", 4, 4, 2, 2, "#ff0000", "", 1, 0],
            ["layer", "base"],
            ["r", 8, 8, 2, 2, "#00ff00", "", 1, 0],
            ["cut", 7],
        ]));
        assert_eq!((drawing.page.len(), drawing.overlay.len()), (2, 1));
        assert_eq!(drawing.cuts[0], Cut { x: 5.0, top: 0.0, bottom: 10.0 });
        assert_eq!((drawing.cuts[1].top, drawing.cuts[1].bottom), (f32::MIN, f32::MAX));
        let page = drawing.paint_page(10, 10).unwrap();
        assert_eq!(at(&page, 4, 4).3, 0);
        let all = drawing.paint_all(10, 10).unwrap();
        assert_eq!(at(&all, 4, 4), (255, 0, 0, 255));
    }

    #[test]
    fn a_piece_is_painted_from_what_reaches_into_it_and_changes_only_with_that() {
        let ops = json!([
            ["r", 0, 0, 10, 10, "#ff0000", "", 1, 0],
            ["g", 30, 20, 40, 0xE0A4, "#ffffff"],
            ["layer", "cursor"],
            ["r", 32, 0, 1, 40, "#00ff00", "", 1, 0],
        ]);
        let drawing = Drawing::parse(&ops);
        let whole = drawing.paint_all(60, 40).unwrap();
        let piece = drawing.paint_piece([24.0, 8.0, 30.0, 24.0], Layers::Both).unwrap();
        for (x, y) in [(0, 0), (6, 12), (8, 4), (29, 23)] {
            assert_eq!(at(&piece, x, y), at(&whole, x + 24, y + 8), "at {x}, {y}");
        }
        let left = [0.0, 0.0, 20.0, 40.0];
        let right = [20.0, 0.0, 40.0, 40.0];
        // The cursor moves: only the piece it is in changes, and only with the overlay.
        let mut moved = ops.clone();
        moved[3][1] = json!(36);
        let after = Drawing::parse(&moved);
        assert_eq!(drawing.piece_key(left, Layers::Both), after.piece_key(left, Layers::Both));
        assert_ne!(drawing.piece_key(right, Layers::Both), after.piece_key(right, Layers::Both));
        assert_eq!(drawing.piece_key(right, Layers::Page), after.piece_key(right, Layers::Page));
        assert_eq!(after.overlay_box(), Some([36.0, 0.0, 1.0, 40.0]));
    }

    #[test]
    fn half_transparent_colours_come_out_straight() {
        let pixmap = Drawing::parse(&json!([["r", 0, 0, 1, 1, "#ff000080", "", 1, 0]])).paint_page(1, 1).unwrap();
        let rgba = straight_rgba(&pixmap);
        assert_eq!(rgba[0], 255);
        assert_eq!(rgba[3], 128);
    }
}
