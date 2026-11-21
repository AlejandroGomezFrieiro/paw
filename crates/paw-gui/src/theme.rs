//! The colours, the type and the drawings the window is made of. Surfaces
//! are neutral greys; colour is kept for state (blue selection, amber
//! playhead and loop, green play, red record, orange mute, yellow solo) and
//! for what belongs to a track (its stripe, clips, notes and name plate).
//!
//! The colours are the kernel's (`paw.canvas.palette`), so that a view an
//! extension paints and the window's own drawing agree; what the palette
//! does not name is kept here.

use std::collections::HashMap;
use std::sync::OnceLock;

use egui::{Color32, FontData, FontDefinitions, FontFamily, FontId, TextureHandle, TextureOptions};
use serde_json::Value;

use crate::icons::Icon;

macro_rules! palette {
    ($($name:ident = $hex:literal),* $(,)?) => {
        /// The window's colours, by the names the kernel's palette uses.
        #[derive(Clone, Debug)]
        pub struct Theme { $(pub $name: Color32,)* }

        impl Theme {
            /// The palette the kernel holds, where it names a colour; the
            /// window's own where it does not.
            pub fn from_palette(palette: &Value) -> Theme {
                Theme { $($name: palette[stringify!($name)].as_str().and_then(hex).unwrap_or(hex($hex).unwrap()),)* }
            }

            /// A colour by its name in the palette (a scene's `tone`).
            pub fn named(&self, name: &str) -> Option<Color32> {
                match name {
                    $(stringify!($name) => Some(self.$name),)*
                    _ => None,
                }
            }
        }
    };
}

palette! {
    // Surfaces, from the back forward.
    surface = "#18191c", lane = "#1f2024", lane_alt = "#1c1d20", panel = "#26272b",
    panel_sel = "#313238", well = "#121315", divider = "#0f1012", card = "#2b2c31",
    card_line = "#3d3f46", control = "#34363c", control_hover = "#3e4047", control_press = "#2a2b30",
    // Grid lines: half beats, beats, bars.
    line_sub = "#25262a", line_beat = "#2c2d32", line_bar = "#3b3d44",
    // Text, by weight; and text on a coloured face.
    text = "#e4e5e8", text_2 = "#a1a3ab", text_3 = "#6b6e77", text_off = "#4a4c53", on_hue = "#121316",
    // States.
    select = "#46b9fe", play = "#fec13a", play_on = "#4ade80", rec = "#ef4444",
    mute = "#f08a3c", solo = "#f2d24b", warn = "#f2c94c", error = "#ff5a4f",
    // Meters, by position: to -18 dB, to -9, to -3, to 0, and over.
    meter_low = "#35c46a", meter_mid = "#a6d84a", meter_high = "#f2d24b", meter_hot = "#f59e3b",
    meter_clip = "#ff3b30", meter_well = "#0e0f11",
    // A keyboard drawn beside a roll.
    key_white = "#d8d9dc", key_black = "#1c1d20", key_line = "#9a9ca3",
    // The window's own: the caps of sliders and faders, faces under the
    // pointer, and the colours of modes and of a few marks.
    thumb = "#c9cbd1", thumb_low = "#a9abb2", bright = "#f4f6fa", accent = "#ffb86b",
    green = "#9ad36a", yellow = "#f2c94c", magenta = "#b79cf2",
}

/// `#rrggbb` or `#rrggbbaa`.
pub fn hex(text: &str) -> Option<Color32> {
    let c: paw_scene::color::Rgba = text.parse().ok()?;
    Some(Color32::from_rgba_unmultiplied(c.r, c.g, c.b, c.a))
}

static THEME: OnceLock<Theme> = OnceLock::new();

/// The window's colours, once the kernel has said them (or the window's own).
pub fn th() -> &'static Theme {
    THEME.get_or_init(|| Theme::from_palette(&Value::Null))
}

pub fn set_theme(theme: Theme) {
    let _ = THEME.set(theme);
}

/// `colour` with `alpha` (0 to 1) of its own.
pub fn alpha(colour: Color32, alpha: f32) -> Color32 {
    let [r, g, b, _] = colour.to_array();
    Color32::from_rgba_unmultiplied(r, g, b, (alpha.clamp(0.0, 1.0) * 255.0) as u8)
}

/// `this` mixed with `other`: `factor` of `this`, the rest of `other`.
pub fn mix(this: Color32, other: Color32, factor: f32) -> Color32 {
    let (a, b) = (this.to_array(), other.to_array());
    let m = |i: usize| (b[i] as f32 + (a[i] as f32 - b[i] as f32) * factor).round() as u8;
    Color32::from_rgba_premultiplied(m(0), m(1), m(2), m(3))
}

/// The colour of a mode of the keyboard, as in the terminal's status line.
pub fn mode_colour(mode: &str) -> Color32 {
    let t = th();
    match mode {
        "x" => t.magenta,
        "i" => t.green,
        "o" => t.yellow,
        "c" => t.accent,
        _ => t.select,
    }
}

// Type: Inter for words, JetBrains Mono for numbers that change. Both are
// built into the program (fonts/), so the window looks the same on any
// machine. Text in a script none of them has (Japanese lyrics) falls back
// on a font of the system's that has it.
pub const T_MICRO: f32 = 9.0;
pub const T_SMALL: f32 = 11.0;
pub const T_BASE: f32 = 12.0;
pub const T_TITLE: f32 = 13.0;
pub const T_CLOCK: f32 = 18.0;

pub fn sans(size: f32) -> FontId {
    FontId::proportional(size)
}
pub fn medium(size: f32) -> FontId {
    FontId::new(size, FontFamily::Name("medium".into()))
}
pub fn semi(size: f32) -> FontId {
    FontId::new(size, FontFamily::Name("semibold".into()))
}
pub fn mono(size: f32) -> FontId {
    FontId::monospace(size)
}
pub fn mono_medium(size: f32) -> FontId {
    FontId::new(size, FontFamily::Name("mono-medium".into()))
}

/// A font of the system's for Chinese, Japanese and Korean, found with
/// fontconfig, read: its bytes and its face in a collection. None where
/// there is none, or none that can be read. Asked on a thread of its own as
/// the program starts, for fontconfig can take a moment.
pub fn cjk_font() -> Option<(Vec<u8>, u32)> {
    let (file, index) = find_cjk()?;
    let bytes = std::fs::read(file).ok()?;
    // A font that does not read would end the program where it is first
    // used: it is tried here, with the parser the drawing uses.
    let face = skrifa::FontRef::from_index(&bytes, index).ok()?;
    use skrifa::MetadataProvider;
    face.charmap().map('さ')?;
    Some((bytes, index))
}

fn find_cjk() -> Option<(std::path::PathBuf, u32)> {
    let out = std::process::Command::new("fc-list")
        .args([":lang=ja:outline=true", "-f", "%{file}|%{index}|%{family}\n"])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let faces: Vec<(&str, u32, &str)> = text
        .lines()
        .filter_map(|line| {
            let mut parts = line.splitn(3, '|');
            let file = parts.next()?;
            // The upper half names an instance of a variable font; the
            // face in the collection is the lower.
            let index = parts.next()?.parse::<u32>().ok()? & 0xffff;
            Some((file, index, parts.next().unwrap_or("")))
        })
        .filter(|(file, _, _)| [".otf", ".ttf", ".ttc", ".otc"].iter().any(|e| file.to_lowercase().ends_with(e)))
        .collect();
    // A sans serif made for Japanese first, then any CJK font, then any.
    let rank = |family: &str| {
        let f = family.to_lowercase();
        match (f.contains("cjk") || f.contains("gothic") || f.contains("jp"), f.contains("sans"), f.contains(" jp")) {
            (true, true, true) => 0,
            (true, true, false) => 1,
            (true, false, _) => 2,
            _ => 3,
        }
    };
    let best = faces.iter().min_by_key(|(_, _, family)| rank(family))?;
    Some((best.0.into(), best.1))
}

/// The bundled fonts, with `cjk` (a file and a face in it) after them where
/// they have no glyph, and the bundled kana after that.
pub fn fonts(cjk: Option<(Vec<u8>, u32)>) -> FontDefinitions {
    let mut fonts = FontDefinitions::default();
    let mut add = |name: &str, bytes: &'static [u8]| {
        fonts.font_data.insert(name.into(), FontData::from_static(bytes).into());
    };
    add("Inter", include_bytes!("../fonts/Inter-Regular.ttf"));
    add("Inter Medium", include_bytes!("../fonts/Inter-Medium.ttf"));
    add("Inter SemiBold", include_bytes!("../fonts/Inter-SemiBold.ttf"));
    add("JetBrains Mono", include_bytes!("../fonts/JetBrainsMono-Regular.ttf"));
    add("JetBrains Mono Medium", include_bytes!("../fonts/JetBrainsMono-Medium.ttf"));
    // Symbols Inter has not (▾ ▸ ◀ ☆) are JetBrains Mono's.
    let mut tail = vec!["JetBrains Mono".to_string()];
    if let Some((bytes, index)) = cjk {
        let mut data = FontData::from_owned(bytes);
        data.index = index;
        fonts.font_data.insert("CJK".into(), data.into());
        tail.push("CJK".into());
    }
    // Where the system has no font for Japanese, kana (a lyric such as さくら)
    // are still drawn: Noto Sans CJK JP cut down to them.
    fonts.font_data.insert("Kana".into(), FontData::from_static(include_bytes!("../fonts/NotoSansJP-Kana.otf")).into());
    tail.push("Kana".into());
    let family = |first: &[&str]| -> Vec<String> {
        first.iter().map(|s| s.to_string()).chain(tail.iter().cloned()).collect()
    };
    fonts.families.insert(FontFamily::Proportional, family(&["Inter"]));
    fonts.families.insert(FontFamily::Name("medium".into()), family(&["Inter Medium", "Inter"]));
    fonts.families.insert(FontFamily::Name("semibold".into()), family(&["Inter SemiBold", "Inter"]));
    fonts.families.insert(FontFamily::Monospace, family(&["JetBrains Mono", "Inter"]));
    fonts
        .families
        .insert(FontFamily::Name("mono-medium".into()), family(&["JetBrains Mono Medium", "JetBrains Mono"]));
    fonts
}

/// The drawings of buttons as textures, made at the size they are drawn at
/// (in the screen's pixels), once for each size.
#[derive(Default)]
pub struct Icons {
    made: HashMap<(usize, u32), TextureHandle>,
}

impl Icons {
    /// The texture of `icon` filled white, `pixels` on a side.
    pub fn get(&mut self, ctx: &egui::Context, icon: Icon, pixels: u32) -> TextureHandle {
        let key = (icon.0.as_ptr() as usize, pixels);
        self.made
            .entry(key)
            .or_insert_with(|| {
                let image = rasterize(icon, pixels);
                ctx.load_texture(format!("icon-{}-{pixels}", key.0), image, TextureOptions::LINEAR)
            })
            .clone()
    }
}

/// An SVG path filled white on a square of `pixels`.
fn rasterize(icon: Icon, pixels: u32) -> egui::ColorImage {
    let size = pixels.max(1);
    let mut pixmap = tiny_skia::Pixmap::new(size, size).expect("a square of some pixels");
    let mut builder = tiny_skia::PathBuilder::new();
    if let Ok(path) = kurbo::BezPath::from_svg(icon.0) {
        use kurbo::PathEl::*;
        let p = |pt: kurbo::Point| (pt.x as f32, pt.y as f32);
        for el in path.elements() {
            match *el {
                MoveTo(a) => builder.move_to(p(a).0, p(a).1),
                LineTo(a) => builder.line_to(p(a).0, p(a).1),
                QuadTo(a, b) => builder.quad_to(p(a).0, p(a).1, p(b).0, p(b).1),
                CurveTo(a, b, c) => builder.cubic_to(p(a).0, p(a).1, p(b).0, p(b).1, p(c).0, p(c).1),
                ClosePath => builder.close(),
            }
        }
    }
    if let Some(path) = builder.finish() {
        let mut paint = tiny_skia::Paint::default();
        paint.set_color_rgba8(255, 255, 255, 255);
        paint.anti_alias = true;
        let scale = size as f32 / icon.1;
        pixmap.fill_path(&path, &paint, tiny_skia::FillRule::EvenOdd, tiny_skia::Transform::from_scale(scale, scale), None);
    }
    egui::ColorImage::from_rgba_premultiplied([size as usize, size as usize], pixmap.data())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_palette_is_the_kernels_where_it_names_a_colour() {
        let theme = Theme::from_palette(&serde_json::json!({ "select": "#010203" }));
        assert_eq!(theme.select, Color32::from_rgb(1, 2, 3));
        assert_eq!(theme.text, hex("#e4e5e8").unwrap(), "the window's own elsewhere");
        assert_eq!(hex("#ff000080").unwrap().a(), 128);
        assert_eq!(hex("nonsense"), None);
    }

    #[test]
    fn an_icon_is_filled_with_its_holes() {
        let image = rasterize(crate::icons::CIRCLE, 32);
        let alpha = |x: usize, y: usize| image.pixels[y * 32 + x].a();
        assert!(alpha(16, 4) > 200, "the ring is drawn");
        assert_eq!(alpha(16, 16), 0, "its middle is a hole");
    }
}
