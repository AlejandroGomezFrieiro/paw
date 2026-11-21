//! A drawing as vector graphics, SVG or PDF: the operations the raster
//! paints, drawn as the same shapes. Glyphs and text are written as their
//! outlines, so a file needs no fonts to be read and looks as the screen
//! does; rectangles, paths and colours (with their transparency) are kept.

use std::fmt::Write as _;
use std::io::Write as _;

use tiny_skia::{Path, PathSegment, Transform};

use crate::fonts::Font;
use crate::{Align, Drawing, Item, Op, Rgba, measure};

/// A shape to draw: path segments already where they go, with how to fill
/// and stroke them.
struct Shape {
    segments: Vec<PathSegment>,
    fill: Option<Rgba>,
    stroke: Option<(Rgba, f32)>,
}

fn moved(path: &Path, at: Transform) -> Vec<PathSegment> {
    let map = |p: tiny_skia::Point| {
        let mut q = [p];
        at.map_points(&mut q);
        q[0]
    };
    path.segments()
        .map(|s| match s {
            PathSegment::MoveTo(p) => PathSegment::MoveTo(map(p)),
            PathSegment::LineTo(p) => PathSegment::LineTo(map(p)),
            PathSegment::QuadTo(a, p) => PathSegment::QuadTo(map(a), map(p)),
            PathSegment::CubicTo(a, b, p) => PathSegment::CubicTo(map(a), map(b), map(p)),
            PathSegment::Close => PathSegment::Close,
        })
        .collect()
}

fn rect_path(x: f32, y: f32, w: f32, h: f32, radius: f32) -> Option<Path> {
    let area = tiny_skia::Rect::from_xywh(x, y, w, h)?;
    if radius > 0.0 {
        crate::rounded(area, radius)
    } else {
        Some(tiny_skia::PathBuilder::from_rect(area))
    }
}

/// A line of text as the shapes of its letters, cut at `right`.
#[allow(clippy::too_many_arguments)]
fn text_shapes(out: &mut Vec<Shape>, font: Font, text: &str, x: f32, baseline: f32, size: f32, colour: Rgba, right: f32) {
    let face = font.face();
    let mut pen = x;
    for c in text.chars() {
        let Some(glyph) = face.glyph_index(c) else { continue };
        let advance = font.advance(glyph) * size;
        if pen + advance > right + 0.5 {
            break;
        }
        if let Some(path) = font.outline(glyph) {
            let at = Transform::from_row(size, 0.0, 0.0, size, pen, baseline);
            out.push(Shape { segments: moved(&path, at), fill: Some(colour), stroke: None });
        }
        pen += advance;
    }
}

fn shapes(items: &[Item]) -> Vec<Shape> {
    let mut out = Vec::new();
    for item in items {
        match &item.op {
            Op::Rect { x, y, w, h, fill, stroke, width, radius } => {
                if let Some(path) = rect_path(*x, *y, *w, *h, *radius) {
                    out.push(Shape { segments: moved(&path, Transform::identity()), fill: *fill, stroke: None });
                }
                if let Some(stroke) = stroke.filter(|s| s.3 > 0 && *width > 0.0) {
                    let half = width / 2.0;
                    if let Some(path) = rect_path(x + half, y + half, w - width, h - width, (radius - half).max(0.0)) {
                        out.push(Shape { segments: moved(&path, Transform::identity()), fill: None, stroke: Some((stroke, *width)) });
                    }
                }
            }
            Op::Text { x, y, text, colour, size, bold, align, width } => {
                let font = if *bold { Font::SansBold } else { Font::Sans };
                let run = measure(font, text, *size);
                let left = match align {
                    Align::Left => *x,
                    Align::Center => x - run.min(*width) / 2.0,
                    Align::Right => x - run.min(*width),
                };
                let baseline = y + font.ascent() * size;
                text_shapes(&mut out, font, text, left, baseline, *size, *colour, left + width);
            }
            Op::Path { path, stroke, width, fill } => {
                let segments = moved(path, Transform::identity());
                out.push(Shape { segments, fill: *fill, stroke: stroke.map(|s| (s, *width)) });
            }
            Op::Mono { x, y, w, h, text, colour, background, attrs } => {
                if let (Some(background), Some(path)) = (background, rect_path(*x, *y, *w, *h, 0.0)) {
                    out.push(Shape { segments: moved(&path, Transform::identity()), fill: Some(*background), stroke: None });
                }
                let font = if attrs & 1 != 0 { Font::MonoBold } else { Font::Mono };
                let size = h / font.line_height();
                let baseline = y + (h - font.line_height() * size) / 2.0 + font.ascent() * size;
                text_shapes(&mut out, font, text, *x, baseline, size, *colour, x + w);
            }
            Op::Glyph { x, y, size, codepoint, colour, font } => {
                if let Some(glyph) = font.face().glyph_index(*codepoint)
                    && let Some(path) = font.outline(glyph)
                {
                    let at = Transform::from_row(*size, 0.0, 0.0, *size, *x, *y);
                    out.push(Shape { segments: moved(&path, at), fill: Some(*colour), stroke: None });
                }
            }
        }
    }
    out
}

fn all(drawing: &Drawing) -> Vec<Shape> {
    let mut list = shapes(&drawing.page);
    list.extend(shapes(&drawing.overlay));
    list
}

fn num(v: f32) -> String {
    let r = (v * 100.0).round() / 100.0;
    if r == r.trunc() { format!("{}", r as i64) } else { format!("{r}") }
}

fn hex(c: Rgba) -> String {
    paw_scene::color::Rgba::rgb(c.0, c.1, c.2).to_string()
}

/// A drawing as an SVG document `width` by `height` pixels.
pub fn svg(drawing: &Drawing, width: f32, height: f32) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">"#,
        w = num(width),
        h = num(height)
    );
    for shape in all(drawing) {
        let mut d = String::new();
        for s in &shape.segments {
            let _ = match s {
                PathSegment::MoveTo(p) => write!(d, "M{} {}", num(p.x), num(p.y)),
                PathSegment::LineTo(p) => write!(d, "L{} {}", num(p.x), num(p.y)),
                PathSegment::QuadTo(a, p) => write!(d, "Q{} {} {} {}", num(a.x), num(a.y), num(p.x), num(p.y)),
                PathSegment::CubicTo(a, b, p) => {
                    write!(d, "C{} {} {} {} {} {}", num(a.x), num(a.y), num(b.x), num(b.y), num(p.x), num(p.y))
                }
                PathSegment::Close => write!(d, "Z"),
            };
        }
        let mut attrs = String::new();
        match shape.fill {
            Some(c) => {
                let _ = write!(attrs, r#" fill="{}""#, hex(c));
                if c.3 < 255 {
                    let _ = write!(attrs, r#" fill-opacity="{}""#, num(c.3 as f32 / 255.0));
                }
            }
            None => attrs.push_str(r#" fill="none""#),
        }
        if let Some((c, w)) = shape.stroke {
            let _ = write!(attrs, r#" stroke="{}" stroke-width="{}""#, hex(c), num(w));
            if c.3 < 255 {
                let _ = write!(attrs, r#" stroke-opacity="{}""#, num(c.3 as f32 / 255.0));
            }
        }
        let _ = writeln!(out, r#"<path d="{d}"{attrs}/>"#);
    }
    out.push_str("</svg>\n");
    out
}

/// Drawings as the pages of a PDF document, each `(drawing, width,
/// height)` in pixels, `scale` points to a pixel (0.75 for 96 to the inch).
pub fn pdf(pages: &[(Drawing, f32, f32)], scale: f32) -> Vec<u8> {
    // The transparencies used, each a graphics state of its own.
    let mut alphas: Vec<u8> = Vec::new();
    let mut streams = Vec::new();
    for (drawing, _, height) in pages {
        let mut c = String::new();
        // Pixels from the top left, y down, as the drawing has them.
        let _ = writeln!(c, "{} 0 0 {} 0 {} cm 0 J 0 j", num(scale), num(-scale), num(height * scale));
        for shape in all(drawing) {
            let mut alpha = 255u8;
            if let Some(f) = shape.fill {
                let _ = writeln!(c, "{} {} {} rg", num(f.0 as f32 / 255.0), num(f.1 as f32 / 255.0), num(f.2 as f32 / 255.0));
                alpha = alpha.min(f.3);
            }
            if let Some((s, w)) = shape.stroke {
                let _ = writeln!(c, "{} {} {} RG {} w", num(s.0 as f32 / 255.0), num(s.1 as f32 / 255.0), num(s.2 as f32 / 255.0), num(w));
                alpha = alpha.min(s.3);
            }
            if alpha < 255 {
                let at = alphas.iter().position(|a| *a == alpha).unwrap_or_else(|| {
                    alphas.push(alpha);
                    alphas.len() - 1
                });
                let _ = writeln!(c, "q /A{at} gs");
            }
            let mut last = tiny_skia::Point::zero();
            for s in &shape.segments {
                let _ = match s {
                    PathSegment::MoveTo(p) => {
                        last = *p;
                        writeln!(c, "{} {} m", num(p.x), num(p.y))
                    }
                    PathSegment::LineTo(p) => {
                        last = *p;
                        writeln!(c, "{} {} l", num(p.x), num(p.y))
                    }
                    PathSegment::QuadTo(a, p) => {
                        // A quadratic as the cubic it is.
                        let toward = |from: tiny_skia::Point| {
                            tiny_skia::Point::from_xy(from.x + (a.x - from.x) * 2.0 / 3.0, from.y + (a.y - from.y) * 2.0 / 3.0)
                        };
                        let (c1, c2) = (toward(last), toward(*p));
                        last = *p;
                        writeln!(c, "{} {} {} {} {} {} c", num(c1.x), num(c1.y), num(c2.x), num(c2.y), num(p.x), num(p.y))
                    }
                    PathSegment::CubicTo(a, b, p) => {
                        last = *p;
                        writeln!(c, "{} {} {} {} {} {} c", num(a.x), num(a.y), num(b.x), num(b.y), num(p.x), num(p.y))
                    }
                    PathSegment::Close => writeln!(c, "h"),
                };
            }
            let paint = match (shape.fill.is_some(), shape.stroke.is_some()) {
                (true, true) => "B",
                (true, false) => "f",
                (false, true) => "S",
                (false, false) => "n",
            };
            let _ = writeln!(c, "{paint}");
            if alpha < 255 {
                let _ = writeln!(c, "Q");
            }
        }
        let mut z = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
        let _ = z.write_all(c.as_bytes());
        streams.push(z.finish().unwrap_or_default());
    }

    // Objects: 1 the catalogue, 2 the pages, 3 the graphics states, then a
    // page and its content for each page.
    let mut objects: Vec<Vec<u8>> = Vec::new();
    objects.push(b"<< /Type /Catalog /Pages 2 0 R >>".to_vec());
    let kids: Vec<String> = (0..pages.len()).map(|i| format!("{} 0 R", 4 + 2 * i)).collect();
    objects.push(format!("<< /Type /Pages /Kids [{}] /Count {} >>", kids.join(" "), pages.len()).into_bytes());
    let states: Vec<String> = alphas
        .iter()
        .enumerate()
        .map(|(i, a)| format!("/A{i} << /Type /ExtGState /ca {0} /CA {0} >>", num(*a as f32 / 255.0)))
        .collect();
    objects.push(format!("<< {} >>", states.join(" ")).into_bytes());
    for (i, ((_, width, height), stream)) in pages.iter().zip(&streams).enumerate() {
        objects.push(
            format!(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {} {}] /Resources << /ExtGState 3 0 R >> /Contents {} 0 R >>",
                num(width * scale),
                num(height * scale),
                5 + 2 * i
            )
            .into_bytes(),
        );
        let mut content = format!("<< /Length {} /Filter /FlateDecode >>\nstream\n", stream.len()).into_bytes();
        content.extend_from_slice(stream);
        content.extend_from_slice(b"\nendstream");
        objects.push(content);
    }
    let mut out = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n".to_vec();
    let mut offsets = Vec::new();
    for (i, body) in objects.iter().enumerate() {
        offsets.push(out.len());
        out.extend_from_slice(format!("{} 0 obj\n", i + 1).as_bytes());
        out.extend_from_slice(body);
        out.extend_from_slice(b"\nendobj\n");
    }
    let xref = out.len();
    out.extend_from_slice(format!("xref\n0 {}\n0000000000 65535 f \n", objects.len() + 1).as_bytes());
    for at in offsets {
        out.extend_from_slice(format!("{at:010} 00000 n \n").as_bytes());
    }
    out.extend_from_slice(format!("trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n", objects.len() + 1).as_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn svg_has_a_path_for_each_shape_and_letters_as_outlines() {
        let drawing = Drawing::parse(&json!([
            ["r", 2, 3, 4, 5, "#ff0000", "", 1, 0],
            ["g", 10, 20, 40, 0xE0A4, "#000000"],
            ["t", 0, 30, "Hi", "#00000080", 14, 0, "left", 100],
            ["p", "M 0 0 L 10 10", "#0000ff", 2, ""],
        ]));
        let text = svg(&drawing, 100.0, 50.0);
        assert!(text.starts_with("<svg") && text.trim_end().ends_with("</svg>"));
        assert!(text.contains(r##"<path d="M2 3L6 3L6 8L2 8Z" fill="#ff0000"/>"##), "{text}");
        assert_eq!(text.matches("<path").count(), 1 + 1 + 2 + 1, "a rect, a glyph, two letters, a line");
        assert!(text.contains(r#"fill-opacity="0.5""#));
        assert!(text.contains(r##"fill="none" stroke="#0000ff" stroke-width="2""##));
    }

    #[test]
    fn pdf_is_a_document_of_its_pages_with_compressed_content() {
        let one = Drawing::parse(&json!([["r", 0, 0, 10, 10, "#ff000080", "", 1, 0]]));
        let two = Drawing::parse(&json!([["g", 10, 20, 40, 0xE050, "#000000"]]));
        let bytes = pdf(&[(one, 800.0, 1100.0), (two, 800.0, 1100.0)], 0.75);
        let find = |what: &str, from: usize| {
            bytes[from..].windows(what.len()).position(|w| w == what.as_bytes()).map(|p| p + from)
        };
        let text = String::from_utf8_lossy(&bytes);
        assert!(text.starts_with("%PDF-1.4"));
        assert!(text.contains("/Count 2"));
        assert!(text.contains("/MediaBox [0 0 600 825]"));
        assert!(text.contains("/ca 0.5"), "a half transparent fill has its state");
        assert!(text.trim_end().ends_with("%%EOF"));
        // Every object is where the cross reference says.
        let xref = find("startxref\n", 0).unwrap();
        let tail = String::from_utf8_lossy(&bytes[xref + 10..]).to_string();
        let at: usize = tail.lines().next().unwrap().parse().unwrap();
        assert_eq!(find("xref", at), Some(at));
        let table = String::from_utf8_lossy(&bytes[at..]).to_string();
        for (i, line) in table.lines().skip(3).take(7).enumerate() {
            let offset: usize = line[..10].parse().unwrap();
            assert_eq!(find(&format!("{} 0 obj", i + 1), offset), Some(offset), "object {}", i + 1);
        }
    }
}
