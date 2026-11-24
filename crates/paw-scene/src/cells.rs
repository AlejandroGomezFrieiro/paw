//! Character cells: what a terminal shows, and what every scene can be
//! lowered to. The kernel's screen (`paw_core::grid`) writes its cells
//! with these functions, and so does [`crate::Scene::to_cells`], so that a
//! scene lowered to cells is the screen a view drew, cell for cell.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_possible_wrap, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use unicode_width::UnicodeWidthChar;

use crate::color::Rgba;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Color {
    /// The terminal's own foreground or background.
    #[default]
    Default,
    Indexed(u8),
    Rgb(u8, u8, u8),
}

impl Color {
    /// Parse `#rrggbb`, `#rgb`, a colour name, or `default`.
    pub fn parse(text: &str) -> Option<Color> {
        if let Some(hex) = text.strip_prefix('#') {
            let digit = |i: usize| u8::from_str_radix(hex.get(i..i + 1)?, 16).ok();
            let pair = |i: usize| u8::from_str_radix(hex.get(i..i + 2)?, 16).ok();
            return match hex.len() {
                6 => Some(Color::Rgb(pair(0)?, pair(2)?, pair(4)?)),
                3 => Some(Color::Rgb(digit(0)? * 17, digit(1)? * 17, digit(2)? * 17)),
                _ => None,
            };
        }
        const NAMES: [&str; 8] = [
            "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
        ];
        let lower = text.to_ascii_lowercase();
        let (bright, base) = match lower.strip_prefix("bright") {
            Some(rest) => (8, rest.trim_start_matches(['_', '-'])),
            None => (0, lower.as_str()),
        };
        match base {
            "default" | "none" => Some(Color::Default),
            "gray" | "grey" => Some(Color::Indexed(8)),
            _ => NAMES
                .iter()
                .position(|n| *n == base)
                .map(|i| Color::Indexed(i as u8 + bright)),
        }
    }
}

/// On the wire a colour is `"default"`, `"#rrggbb"`, or the number of one
/// of the 256 indexed colours.
impl Serialize for Color {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        match *self {
            Color::Default => s.serialize_str("default"),
            Color::Indexed(i) => s.serialize_u8(i),
            Color::Rgb(r, g, b) => s.collect_str(&Rgba::rgb(r, g, b)),
        }
    }
}

impl<'de> Deserialize<'de> for Color {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        match serde_json::Value::deserialize(d)? {
            serde_json::Value::Number(n) => Ok(Color::Indexed(n.as_u64().unwrap_or(0).min(255) as u8)),
            serde_json::Value::String(s) => {
                Color::parse(&s).ok_or_else(|| serde::de::Error::custom(format!("bad colour `{s}`")))
            }
            other => Err(serde::de::Error::custom(format!("bad colour {other}"))),
        }
    }
}

pub const BOLD: u8 = 1;
pub const DIM: u8 = 2;
pub const ITALIC: u8 = 4;
pub const UNDERLINE: u8 = 8;
pub const REVERSE: u8 = 16;
pub const STRIKE: u8 = 32;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cell {
    /// `'\0'` marks the second half of a double-width character.
    pub ch: char,
    pub fg: Color,
    pub bg: Color,
    pub attrs: u8,
}

impl Default for Cell {
    fn default() -> Self {
        Self {
            ch: ' ',
            fg: Color::Default,
            bg: Color::Default,
            attrs: 0,
        }
    }
}

/// A change to apply to cells. Anything left `None` keeps what the cell had,
/// so text can be drawn over a background that was filled earlier.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct Style {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fg: Option<Color>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bg: Option<Color>,
    #[serde(skip_serializing_if = "is_default")]
    pub on: u8,
    #[serde(skip_serializing_if = "is_default")]
    pub off: u8,
}

/// Whether a field has the value that a frontend takes when the field is
/// left out of the wire.
fn is_default<T: Default + PartialEq>(value: &T) -> bool {
    *value == T::default()
}

impl Style {
    pub fn apply(&self, cell: &mut Cell) {
        if let Some(fg) = self.fg {
            cell.fg = fg;
        }
        if let Some(bg) = self.bg {
            cell.bg = bg;
        }
        cell.attrs = (cell.attrs | self.on) & !self.off;
    }

    /// Whether it changes nothing.
    pub fn is_plain(&self) -> bool {
        *self == Style::default()
    }
}

/// A rectangle of cells: position, then size.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

impl Rect {
    pub fn intersect(&self, other: &Rect) -> Rect {
        let x = self.x.max(other.x);
        let y = self.y.max(other.y);
        let right = (self.x + self.w).min(other.x + other.w);
        let bottom = (self.y + self.h).min(other.y + other.h);
        Rect {
            x,
            y,
            w: (right - x).max(0),
            h: (bottom - y).max(0),
        }
    }

    pub fn contains(&self, x: i32, y: i32) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }
}

/// The rectangle a row-major slice of cells `width` wide covers.
fn bounds(cells: &[Cell], width: u16) -> Rect {
    let w = width as i32;
    Rect { x: 0, y: 0, w, h: if w > 0 { cells.len() as i32 / w } else { 0 } }
}

/// Draw text into cells (row by row, `width` to a row) starting at `(x, y)`,
/// keeping inside `clip`. `touched` hears of every cell written. Returns how
/// many columns the text takes, whether or not all of it was visible.
#[expect(clippy::too_many_arguments, reason = "one argument for each value of a text run or a shape; a struct for them is open work")]
pub fn write_text(
    cells: &mut [Cell],
    width: u16,
    clip: Rect,
    x: i32,
    y: i32,
    text: &str,
    style: Style,
    mut touched: impl FnMut(i32, i32),
) -> i32 {
    let clip = clip.intersect(&bounds(cells, width));
    let row = width as usize;
    let mut col = x;
    for ch in text.chars() {
        let w = ch.width().unwrap_or(0) as i32;
        if w == 0 {
            continue;
        }
        // A column past the largest i32 is off any screen: the sums stop
        // there and do not overflow.
        let last = col.saturating_add(w - 1);
        if clip.contains(col, y) && clip.contains(last, y) {
            touched(col, y);
            touched(last, y);
            let at = y as usize * row + col as usize;
            cells[at].ch = ch;
            style.apply(&mut cells[at]);
            if w == 2 {
                cells[at + 1].ch = '\0';
                style.apply(&mut cells[at + 1]);
            }
        }
        col = col.saturating_add(w);
    }
    col - x
}

/// Restyle an area of cells and, when `ch` is given, overwrite its
/// characters. `touched` hears of every cell written.
pub fn write_fill(
    cells: &mut [Cell],
    width: u16,
    clip: Rect,
    area: Rect,
    ch: Option<char>,
    style: Style,
    mut touched: impl FnMut(i32, i32),
) {
    let area = area.intersect(&clip).intersect(&bounds(cells, width));
    let row = width as usize;
    for y in area.y..area.y + area.h {
        for x in area.x..area.x + area.w {
            touched(x, y);
            let cell = &mut cells[y as usize * row + x as usize];
            if let Some(ch) = ch {
                cell.ch = ch;
            }
            style.apply(cell);
        }
    }
}

/// A colour as red, green and blue, with `default` for the terminal's own.
/// The 256 indexed colours are xterm's.
pub fn rgb(color: Color, default: (u8, u8, u8)) -> (u8, u8, u8) {
    const BASE: [(u8, u8, u8); 16] = [
        (0x00, 0x00, 0x00),
        (0xcd, 0x31, 0x31),
        (0x0d, 0xbc, 0x79),
        (0xe5, 0xe5, 0x10),
        (0x24, 0x72, 0xc8),
        (0xbc, 0x3f, 0xbc),
        (0x11, 0xa8, 0xcd),
        (0xe5, 0xe5, 0xe5),
        (0x66, 0x66, 0x66),
        (0xf1, 0x4c, 0x4c),
        (0x23, 0xd1, 0x8b),
        (0xf5, 0xf5, 0x43),
        (0x3b, 0x8e, 0xea),
        (0xd6, 0x70, 0xd6),
        (0x29, 0xb8, 0xdb),
        (0xff, 0xff, 0xff),
    ];
    match color {
        Color::Default => default,
        Color::Rgb(r, g, b) => (r, g, b),
        Color::Indexed(i) if i < 16 => BASE[i as usize],
        Color::Indexed(i) if i < 232 => {
            let level = |n: u8| if n == 0 { 0 } else { 55 + 40 * n };
            let i = i - 16;
            (level(i / 36), level(i / 6 % 6), level(i % 6))
        }
        Color::Indexed(i) => {
            let grey = 8 + 10 * (i - 232);
            (grey, grey, grey)
        }
    }
}

/// A stretch of a row in one style, for a frontend that draws text rather
/// than cells: the column it starts at and how many it takes, its text, its
/// colours as `#rrggbb`, and what is left of its attributes (bold, italic,
/// underline, strike). Reverse and dim are already in its colours.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Run {
    pub x: u16,
    pub w: u16,
    pub text: String,
    pub fg: String,
    pub bg: String,
    pub attrs: u8,
}

/// Cells (row by row, `width` to a row) as rows of runs of one style each,
/// with the terminal's own colours given as `fg` and `bg`.
pub fn runs(cells: &[Cell], width: u16, fg: (u8, u8, u8), bg: (u8, u8, u8)) -> Vec<Vec<Run>> {
    let width = width.max(1) as usize;
    cells
        .chunks(width)
        .map(|row| {
            let mut runs: Vec<Run> = Vec::new();
            for (x, cell) in row.iter().enumerate() {
                let (mut front, mut back) = (rgb(cell.fg, fg), rgb(cell.bg, bg));
                if cell.attrs & REVERSE != 0 {
                    (front, back) = (back, front);
                }
                if cell.attrs & DIM != 0 {
                    let mix = |a: u8, b: u8| ((a as u16 + b as u16) / 2) as u8;
                    front = (mix(front.0, back.0), mix(front.1, back.1), mix(front.2, back.2));
                }
                let attrs = cell.attrs & (BOLD | ITALIC | UNDERLINE | STRIKE);
                let (front, back) = (Rgba::from(front).to_string(), Rgba::from(back).to_string());
                match runs.last_mut() {
                    Some(run) if run.fg == front && run.bg == back && run.attrs == attrs => {
                        run.w += 1;
                        if cell.ch != '\0' {
                            run.text.push(cell.ch);
                        }
                    }
                    // The second half of a wide character goes with its first.
                    Some(run) if cell.ch == '\0' => run.w += 1,
                    _ => runs.push(Run {
                        x: x as u16,
                        w: 1,
                        text: if cell.ch == '\0' { String::new() } else { cell.ch.to_string() },
                        fg: front,
                        bg: back,
                        attrs,
                    }),
                }
            }
            runs
        })
        .collect()
}

/// A rectangle of cells of its own: a scene lowered to cells.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Cells {
    pub width: u16,
    pub height: u16,
    pub cells: Vec<Cell>,
}

impl Cells {
    pub fn new(width: u16, height: u16) -> Self {
        Self { width, height, cells: vec![Cell::default(); width as usize * height as usize] }
    }

    pub fn rect(&self) -> Rect {
        bounds(&self.cells, self.width)
    }

    pub fn text(&mut self, clip: Rect, x: i32, y: i32, text: &str, style: Style) -> i32 {
        write_text(&mut self.cells, self.width, clip, x, y, text, style, |_, _| {})
    }

    pub fn fill(&mut self, clip: Rect, area: Rect, ch: Option<char>, style: Style) {
        write_fill(&mut self.cells, self.width, clip, area, ch, style, |_, _| {})
    }

    pub fn runs(&self, fg: (u8, u8, u8), bg: (u8, u8, u8)) -> Vec<Vec<Run>> {
        runs(&self.cells, self.width, fg, bg)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_and_fills_keep_what_a_style_leaves_alone() {
        let mut cells = Cells::new(6, 1);
        let clip = cells.rect();
        let blue = Style { bg: Some(Color::Rgb(0, 0, 255)), ..Style::default() };
        cells.fill(clip, clip, Some('.'), blue);
        cells.text(clip, 1, 0, "ab", Style { fg: Some(Color::Indexed(1)), on: BOLD, ..Style::default() });
        // Restyled, not rewritten: the letters stay, bold goes.
        cells.fill(clip, Rect { x: 2, y: 0, w: 2, h: 1 }, None, Style { off: BOLD, ..Style::default() });
        let row = &cells.cells;
        assert_eq!(row.iter().map(|c| c.ch).collect::<String>(), ".ab...");
        assert_eq!((row[1].attrs, row[2].attrs), (BOLD, 0));
        assert_eq!(row[2].bg, Color::Rgb(0, 0, 255), "the background filled first stays under the text");
    }

    #[test]
    fn a_wide_character_takes_two_cells_and_is_left_out_where_it_does_not_fit() {
        let mut cells = Cells::new(4, 1);
        let used = cells.text(Rect { x: 0, y: 0, w: 3, h: 1 }, 0, 0, "界界", Style::default());
        assert_eq!(used, 4, "the columns it takes, shown or not");
        assert_eq!(cells.cells.iter().map(|c| c.ch).collect::<Vec<_>>(), vec!['界', '\0', ' ', ' ']);
    }

    // Found while writing the fuzz target `remote`: a far
    // terminal is sent text at any column, and a column past the largest
    // i32 overflowed.
    #[test]
    fn text_at_the_last_column_of_i32_is_off_the_screen() {
        let mut cells = Cells::new(4, 1);
        let used = cells.text(cells.rect(), i32::MAX, 0, "界ab", Style::default());
        assert_eq!(used, 0, "no column is left to take");
        assert!(cells.cells.iter().all(|c| c.ch == ' '));
    }

    #[test]
    fn colours_go_on_the_wire_as_names_hex_or_numbers() {
        let style = Style { fg: Some(Color::Rgb(1, 2, 3)), bg: Some(Color::Default), on: BOLD, off: 0 };
        let text = serde_json::to_string(&style).unwrap();
        assert_eq!(text, r##"{"fg":"#010203","bg":"default","on":1}"##);
        assert_eq!(serde_json::from_str::<Style>(&text).unwrap(), style);
        assert_eq!(serde_json::from_str::<Style>(r#"{"fg":196}"#).unwrap().fg, Some(Color::Indexed(196)));
    }
}
