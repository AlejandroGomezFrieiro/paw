//! The fonts a drawing is drawn in, built into the program: three SMuFL
//! music fonts (Leland, Bravura, Petaluma, all under the SIL Open Font
//! License, licences beside them in `fonts/`) with their metadata, and the
//! window's own Inter and JetBrains Mono for text.
//!
//! The music fonts and their metadata are MuseScore's copies (tag v4.4.4,
//! `fonts/<name>/`); the metadata is cut down to what engraving reads
//! (`engravingDefaults`, `glyphBBoxes`, `glyphsWithAnchors`), and SMuFL's
//! `glyphnames.json` to names and code points.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use serde_json::Value;
use tiny_skia::{Path, PathBuilder, PathSegment};
use ttf_parser::{Face, GlyphId, OutlineBuilder};

/// The outlines of glyphs read so far, by font and glyph (`None`: no outline).
type Outlines = HashMap<(Font, u16), Option<Arc<Path>>>;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Font {
    Leland,
    Bravura,
    Petaluma,
    Sans,
    SansBold,
    Mono,
    MonoBold,
}

const DATA: [&[u8]; 7] = [
    include_bytes!("../fonts/Leland.otf"),
    include_bytes!("../fonts/Bravura.otf"),
    include_bytes!("../fonts/Petaluma.otf"),
    include_bytes!("../../paw-gui/fonts/Inter-Regular.ttf"),
    include_bytes!("../../paw-gui/fonts/Inter-SemiBold.ttf"),
    include_bytes!("../../paw-gui/fonts/JetBrainsMono-Regular.ttf"),
    include_bytes!("../../paw-gui/fonts/JetBrainsMono-Medium.ttf"),
];

const METADATA: [&str; 3] = [
    include_str!("../fonts/leland_metadata.json"),
    include_str!("../fonts/bravura_metadata.json"),
    include_str!("../fonts/petaluma_metadata.json"),
];

/// The music fonts by name, the first the default.
pub const MUSIC: [(&str, Font); 3] = [
    ("Leland", Font::Leland),
    ("Bravura", Font::Bravura),
    ("Petaluma", Font::Petaluma),
];

impl Font {
    /// A music font by name, any case; the default for nothing.
    pub fn music(name: Option<&str>) -> Option<Font> {
        match name.filter(|n| !n.is_empty()) {
            None => Some(Font::Leland),
            Some(name) => MUSIC
                .iter()
                .find(|(n, _)| n.eq_ignore_ascii_case(name))
                .map(|(_, font)| *font),
        }
    }

    pub fn face(self) -> &'static Face<'static> {
        static FACES: OnceLock<Vec<Face<'static>>> = OnceLock::new();
        let faces = FACES.get_or_init(|| {
            DATA.iter()
                .map(|data| Face::parse(data, 0).expect("a font built into the program"))
                .collect()
        });
        &faces[self as usize]
    }

    /// The outline of a glyph in units of the font's em, y down, from a
    /// cache: a clef drawn a thousand times is read from the font once.
    pub fn outline(self, glyph: GlyphId) -> Option<Arc<Path>> {
        static CACHE: OnceLock<Mutex<Outlines>> = OnceLock::new();
        let cache = CACHE.get_or_init(Default::default);
        if let Some(found) = cache.lock().expect("a thread panicked while it held the lock").get(&(self, glyph.0)) {
            return found.clone();
        }
        let face = self.face();
        let mut builder = Outline {
            path: PathBuilder::new(),
            scale: 1.0 / face.units_per_em() as f32,
        };
        let path = face
            .outline_glyph(glyph, &mut builder)
            .and_then(|_| builder.path.finish())
            .map(Arc::new);
        cache.lock().expect("a thread panicked while it held the lock").insert((self, glyph.0), path.clone());
        path
    }

    /// How far a glyph moves the pen, in ems.
    pub fn advance(self, glyph: GlyphId) -> f32 {
        let face = self.face();
        face.glyph_hor_advance(glyph).unwrap_or(0) as f32 / face.units_per_em() as f32
    }

    /// The height above the baseline the font is laid out with, in ems.
    pub fn ascent(self) -> f32 {
        let face = self.face();
        face.ascender() as f32 / face.units_per_em() as f32
    }

    /// The height of a line, in ems.
    pub fn line_height(self) -> f32 {
        let face = self.face();
        (face.ascender() as f32 - face.descender() as f32 + face.line_gap() as f32)
            / face.units_per_em() as f32
    }
}

struct Outline {
    path: PathBuilder,
    scale: f32,
}

// Font units go up; pixels go down.
impl OutlineBuilder for Outline {
    fn move_to(&mut self, x: f32, y: f32) {
        self.path.move_to(x * self.scale, -y * self.scale);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.path.line_to(x * self.scale, -y * self.scale);
    }
    fn quad_to(&mut self, x1: f32, y1: f32, x: f32, y: f32) {
        let s = self.scale;
        self.path.quad_to(x1 * s, -y1 * s, x * s, -y * s);
    }
    fn curve_to(&mut self, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) {
        let s = self.scale;
        self.path.cubic_to(x1 * s, -y1 * s, x2 * s, -y2 * s, x * s, -y * s);
    }
    fn close(&mut self) {
        self.path.close();
    }
}

/// A music font's SMuFL metadata: `fontName`, `fontVersion`,
/// `engravingDefaults` (thicknesses and the like, in staff spaces),
/// `glyphBBoxes` and `glyphsWithAnchors` (by glyph name, in staff spaces,
/// y up), and `glyphs`, every SMuFL glyph name with its code point.
pub fn smufl(name: Option<&str>) -> Option<Value> {
    static PARSED: OnceLock<Vec<Value>> = OnceLock::new();
    let font = Font::music(name)?;
    let parsed = PARSED.get_or_init(|| {
        let names: Value =
            serde_json::from_str(include_str!("../fonts/glyphnames.json")).unwrap_or_default();
        METADATA
            .iter()
            .map(|text| {
                let mut value: Value = serde_json::from_str(text).unwrap_or_default();
                value["glyphs"] = names.clone();
                value
            })
            .collect()
    });
    parsed.get(font as usize).cloned()
}

/// A music font's glyph as path commands, `["M", x, y, "C", ...]`, in staff
/// spaces from its origin, y down: for a frontend that cannot draw the font
/// and is given each glyph as a path. Nothing for a glyph it has not.
pub fn glyph_outline(name: Option<&str>, codepoint: u32) -> Option<Vec<Value>> {
    let font = Font::music(name)?;
    let glyph = font.face().glyph_index(char::from_u32(codepoint)?)?;
    let path = font.outline(glyph)?;
    // An em is four staff spaces; a thousandth of a space is fine enough.
    let n = |v: f32| Value::from((v as f64 * 4000.0).round() / 1000.0);
    let mut out = Vec::new();
    for segment in path.segments() {
        match segment {
            PathSegment::MoveTo(p) => out.extend(["M".into(), n(p.x), n(p.y)]),
            PathSegment::LineTo(p) => out.extend(["L".into(), n(p.x), n(p.y)]),
            PathSegment::QuadTo(a, p) => out.extend(["Q".into(), n(a.x), n(a.y), n(p.x), n(p.y)]),
            PathSegment::CubicTo(a, b, p) => {
                out.extend(["C".into(), n(a.x), n(a.y), n(b.x), n(b.y), n(p.x), n(p.y)])
            }
            PathSegment::Close => out.push("Z".into()),
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_font_built_in_parses_and_draws_its_glyphs() {
        for font in [
            Font::Leland,
            Font::Bravura,
            Font::Petaluma,
            Font::Sans,
            Font::SansBold,
            Font::Mono,
            Font::MonoBold,
        ] {
            let face = font.face();
            let probe = if (font as usize) < 3 { '\u{E050}' } else { 'A' };
            let glyph = face.glyph_index(probe).expect("the font has its glyph");
            let path = font.outline(glyph).expect("an outline");
            assert!(path.bounds().width() > 0.1, "{font:?}");
        }
    }

    #[test]
    fn a_treble_clef_sits_on_its_line_as_the_metadata_says() {
        // The G clef's origin is on the G line; its box reaches about four
        // staff spaces up and two and a half down (an em is four spaces).
        let meta = smufl(None).unwrap();
        let bbox = &meta["glyphBBoxes"]["gClef"];
        let (ne, sw) = (bbox["bBoxNE"][1].as_f64().unwrap(), bbox["bBoxSW"][1].as_f64().unwrap());
        assert_eq!(meta["glyphs"]["gClef"], 0xE050);
        let font = Font::Leland;
        let path = font.outline(font.face().glyph_index('\u{E050}').unwrap()).unwrap();
        let b = path.bounds();
        assert!(((-b.top() * 4.0) as f64 - ne).abs() < 0.05, "{} against {ne}", -b.top() * 4.0);
        assert!(((-b.bottom() * 4.0) as f64 - sw).abs() < 0.05);
        assert!(meta["engravingDefaults"]["staffLineThickness"].as_f64().unwrap() > 0.05);
        assert!(smufl(Some("bravura")).is_some() && smufl(Some("petaluma")).is_some());
        assert!(smufl(Some("Comic Sans")).is_none());
    }

    #[test]
    fn a_glyph_outline_is_given_in_staff_spaces() {
        // A black note head is about 1.3 spaces wide and a space high.
        let path = glyph_outline(None, 0xE0A4).unwrap();
        assert_eq!(path[0], "M");
        let numbers: Vec<f64> = path.iter().filter_map(Value::as_f64).collect();
        assert!(numbers.iter().all(|v| v.abs() < 1.5), "{numbers:?}");
        assert!(numbers.iter().cloned().fold(0.0, f64::max) > 1.2);
        assert!(glyph_outline(Some("Comic Sans"), 0xE0A4).is_none());
    }
}
