//! The screen: a grid of styled character cells that Lua draws into and
//! frontends display. This is the whole contract between the UI code and
//! whatever is showing it.

use std::collections::HashMap;

pub use paw_scene::cells::{BOLD, Cell, Color, DIM, ITALIC, REVERSE, Rect, STRIKE, Style, UNDERLINE, rgb};
pub(crate) use paw_scene::cells::Run;
use paw_scene::color::Rgba;

/// What a terminal can show besides cells, as its frontend found out when
/// it started (or a remote one said with `ui.attach`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Caps {
    /// Images by the kitty graphics protocol.
    pub graphics: bool,
    /// The size of a cell in pixels; 0 when the terminal does not say.
    pub cell: (u16, u16),
    /// The pointer reported in pixels (mode 1016).
    pub pixel_mouse: bool,
    /// The terminal's own foreground and background colours, when it said.
    pub fg: Option<(u8, u8, u8)>,
    pub bg: Option<(u8, u8, u8)>,
    /// Strips can be placed under the text (a negative z): in any terminal
    /// that shows images. Where a coloured background would hide them
    /// (Konsole), the terminal's frontend paints it into the picture.
    pub under: bool,
}

impl Caps {
    /// Whether a view can be shown in pixels on this terminal.
    pub fn pixels(&self) -> bool {
        self.graphics && self.cell.0 > 0 && self.cell.1 > 0
    }

    pub fn to_json(&self) -> serde_json::Value {
        let colour = |c: Option<(u8, u8, u8)>| c.map(|c| Rgba::from(c).to_string());
        serde_json::json!({
            "graphics": self.graphics, "cell": [self.cell.0, self.cell.1],
            "pixel_mouse": self.pixel_mouse, "fg": colour(self.fg), "bg": colour(self.bg),
            "under": self.under,
        })
    }

    pub fn from_json(value: &serde_json::Value) -> Caps {
        let colour = |v: &serde_json::Value| match v.as_str().and_then(Color::parse) {
            Some(Color::Rgb(r, g, b)) => Some((r, g, b)),
            _ => None,
        };
        let size = |v: &serde_json::Value| v.as_u64().unwrap_or(0).min(1000) as u16;
        Caps {
            graphics: value["graphics"].as_bool().unwrap_or(false),
            cell: (size(&value["cell"][0]), size(&value["cell"][1])),
            pixel_mouse: value["pixel_mouse"].as_bool().unwrap_or(false),
            fg: colour(&value["fg"]),
            bg: colour(&value["bg"]),
            under: value["under"].as_bool().unwrap_or(false),
        }
    }
}

/// Cells a view shows pixels in (a strip, `buf:strip`, or `buf:surface`):
/// its drawing, the operations of `paw.canvas`, for the frontend to make
/// into pixels at `cell` pixels a cell, and which of its cells something
/// drawn after it covers (a menu, a floating view), where the pixels must
/// not show.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Surface {
    /// What the strip is: images and their placements are kept by it, so
    /// two strips of one view, or one view in two windows, are apart.
    pub key: String,
    pub rect: Rect,
    pub cell: (u16, u16),
    /// Placed under the text: its cells are drawn by the view as usual and
    /// show above the picture.
    pub under: bool,
    /// A flag for each cell, row by row.
    pub covered: Vec<bool>,
    pub ops: std::sync::Arc<serde_json::Value>,
    /// Still being drawn by its view ([`Grid::seal_surfaces`]): what is
    /// written in its cells now is the view's own, not something over it.
    pub open: bool,
    /// How many cells of the whole strip are left of and above what shows
    /// (`rect`), when part of it is off its window: a clip scrolled in.
    pub offset: (i32, i32),
    /// The whole strip's size in cells, when part of it is off its window;
    /// (0, 0) when all of it shows. Its drawing is of the whole, so that
    /// scrolling it moves pieces already made.
    pub whole: (i32, i32),
}

impl Surface {
    /// The whole strip's size in cells: what shows, and what is off its window.
    pub fn whole(&self) -> (i32, i32) {
        if self.whole == (0, 0) { (self.rect.w, self.rect.h) } else { self.whole }
    }

    pub fn is_covered(&self, col: u16, row: u16) -> bool {
        self.covered
            .get(row as usize * self.rect.w.max(0) as usize + col as usize)
            .copied()
            .unwrap_or(false)
    }

    /// Covered cells as runs along rows: `[col, row, cols]` each, from the
    /// surface's corner.
    pub fn covered_runs(&self) -> Vec<[u16; 3]> {
        let w = self.rect.w.max(0) as usize;
        let mut out = Vec::new();
        for (row, cells) in self.covered.chunks(w.max(1)).enumerate() {
            let mut col = 0;
            while col < cells.len() {
                if cells[col] {
                    let start = col;
                    while col < cells.len() && cells[col] {
                        col += 1;
                    }
                    out.push([start as u16, row as u16, (col - start) as u16]);
                } else {
                    col += 1;
                }
            }
        }
        out
    }
}

/// The cells of an area of a frame, kept to be put back on a later one when
/// what they were drawn from has not changed (`paw.api.grid_keep`).
pub struct KeptCells {
    rect: Rect,
    /// Row by row.
    cells: Vec<Cell>,
}

/// A part of the screen that moves on its own while the song plays (the
/// playhead, a meter, the status line), drawn again by itself between whole
/// frames ([`Grid::live_restore`]). It keeps what its cells held before it
/// was drawn, what it drew, and what was drawn over it after, which stays.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Live {
    pub rect: Rect,
    /// The cells before it was drawn, row by row.
    under: Vec<Cell>,
    /// The cells as it drew them.
    drawn: Vec<Cell>,
    /// The cells that something not live drew over it after (a menu, a
    /// float): their index in the grid and what they show.
    over: Vec<(usize, Cell)>,
    /// Kept as it was ([`Grid::live_keep`]): what is over it is known.
    kept: bool,
}

#[derive(Clone, Default, PartialEq)]
pub struct Grid {
    pub width: u16,
    pub height: u16,
    pub cells: Vec<Cell>,
    /// The terminal keeps the pointer for its own selection instead of
    /// reporting it (`paw.opt.mouse` off); set by the runtime as it draws.
    pub mouse_off: bool,
    pub surfaces: Vec<Surface>,
    /// The live parts of the frame, in the order they were drawn.
    pub live: Vec<Live>,
    /// While the live parts are drawn again: the ones of the frame before,
    /// whose cells drawn over them go back over the new ones.
    live_before: Vec<Live>,
    /// A live part drawn again drew other cells than before.
    live_changed: bool,
    /// The buffers of live parts done with, to fill again.
    spare: Spare,
}

/// Buffers of live parts done with, to use again: a frame that draws only
/// its live parts allocates none. They are not part of what a grid shows:
/// two grids are equal whatever they keep here, and a copy keeps none.
#[derive(Default)]
struct Spare {
    cells: Vec<Vec<Cell>>,
    over: Vec<Vec<(usize, Cell)>>,
}

impl Spare {
    fn take_cells(&mut self) -> Vec<Cell> {
        self.cells.pop().unwrap_or_default()
    }

    fn give(&mut self, parts: &mut Vec<Live>) {
        for part in parts.drain(..) {
            self.cells.push(part.under);
            self.cells.push(part.drawn);
            self.over.push(part.over);
        }
    }
}

impl Clone for Spare {
    fn clone(&self) -> Self {
        Self::default()
    }
}

impl PartialEq for Spare {
    fn eq(&self, _: &Self) -> bool {
        true
    }
}

impl Grid {
    pub fn new(width: u16, height: u16) -> Self {
        Self {
            width,
            height,
            cells: vec![Cell::default(); width as usize * height as usize],
            mouse_off: false,
            surfaces: Vec::new(),
            live: Vec::new(),
            live_before: Vec::new(),
            live_changed: false,
            spare: Spare::default(),
        }
    }

    pub fn resize(&mut self, width: u16, height: u16) {
        *self = Self::new(width, height);
    }

    pub fn clear(&mut self) {
        self.cells.fill(Cell::default());
        self.surfaces.clear();
        self.live.clear();
        self.live_before.clear();
    }

    /// Keep what the screen shows in `into` (what a frontend was shown
    /// last): the cells, the surfaces and the pointer, not the live parts,
    /// and in the memory it has when it is as big.
    pub fn copy_shown(&self, into: &mut Option<Grid>) {
        match into {
            Some(shown) if shown.cells.len() == self.cells.len() => {
                shown.width = self.width;
                shown.height = self.height;
                shown.cells.copy_from_slice(&self.cells);
                shown.mouse_off = self.mouse_off;
                shown.surfaces.clone_from(&self.surfaces);
            }
            _ => {
                *into = Some(Grid {
                    width: self.width,
                    height: self.height,
                    cells: self.cells.clone(),
                    mouse_off: self.mouse_off,
                    surfaces: self.surfaces.clone(),
                    ..Grid::default()
                });
            }
        }
    }

    /// The cells of `rect`, which is inside the grid, row by row.
    fn cells_of(&self, rect: Rect) -> Vec<Cell> {
        let mut out = Vec::new();
        self.cells_into(rect, &mut out);
        out
    }

    /// [`Grid::cells_of`] into `out`, in the memory it has.
    fn cells_into(&self, rect: Rect, out: &mut Vec<Cell>) {
        out.clear();
        out.reserve((rect.w * rect.h).max(0) as usize);
        let width = self.width as usize;
        for y in rect.y..rect.y + rect.h {
            let at = y as usize * width + rect.x as usize;
            out.extend_from_slice(&self.cells[at..at + rect.w as usize]);
        }
    }

    /// The cells of `area` as they are now, to put back on a later frame
    /// ([`Grid::put_kept`]): nothing when it is off the screen.
    pub fn keep(&self, area: Rect) -> Option<KeptCells> {
        let rect = area.intersect(&self.rect());
        (rect.w > 0 && rect.h > 0).then(|| KeptCells { rect, cells: self.cells_of(rect) })
    }

    /// Put kept cells back where they were kept, if `area` is where they
    /// were kept from: true when it is.
    pub fn put_kept(&mut self, area: Rect, kept: &KeptCells) -> bool {
        let rect = area.intersect(&self.rect());
        if rect != kept.rect {
            return false;
        }
        let (width, w) = (self.width as usize, rect.w as usize);
        for (row, cells) in kept.cells.chunks(w).enumerate() {
            let at = (rect.y as usize + row) * width + rect.x as usize;
            self.cells[at..at + w].copy_from_slice(cells);
        }
        true
    }

    /// A live part is about to be drawn over `area`: keep what is under it.
    /// Returns its number for [`Grid::live_end`], or nothing when it is off
    /// the screen.
    pub fn live_begin(&mut self, area: Rect) -> Option<usize> {
        let rect = area.intersect(&self.rect());
        if rect.w <= 0 || rect.h <= 0 {
            return None;
        }
        let mut under = self.spare.take_cells();
        self.cells_into(rect, &mut under);
        let (drawn, over) = (self.spare.take_cells(), self.spare.over.pop().unwrap_or_default());
        self.live.push(Live { rect, under, drawn, over, kept: false });
        Some(self.live.len() - 1)
    }

    /// The live part `index` is drawn. When it is drawn again by itself, what
    /// the frame before drew over it goes back on top.
    pub fn live_end(&mut self, index: usize) {
        let Some(rect) = self.live.get(index).map(|l| l.rect) else { return };
        let mut drawn = std::mem::take(&mut self.live[index].drawn);
        self.cells_into(rect, &mut drawn);
        match self.live_before.get(index) {
            Some(before) if before.rect == rect => {
                if before.drawn != drawn {
                    self.live_changed = true;
                }
                for &(at, cell) in &before.over {
                    self.cells[at] = cell;
                }
            }
            _ => self.live_changed = true,
        }
        self.live[index].drawn = drawn;
    }

    /// The live part `index` of the frame drawn last did not change: put
    /// its cells back as it drew them, with what was drawn over it, and do
    /// not draw it again. It takes the place of a [`Grid::live_begin`] and
    /// [`Grid::live_end`] pair. Returns its number, or nothing when the
    /// part must be drawn: there is no such part, or a part before it
    /// changed what is under it.
    pub fn live_keep(&mut self, index: usize) -> Option<usize> {
        let before = self.live_before.get(index)?;
        let rect = before.rect;
        if rect != rect.intersect(&self.rect()) || before.drawn.is_empty() || !self.cells_are(rect, &before.under) {
            return None;
        }
        let before = &mut self.live_before[index];
        // Only live parts are drawn between whole frames, so what is not
        // live over this part is what was over it before.
        let part = Live {
            rect,
            under: std::mem::take(&mut before.under),
            drawn: std::mem::take(&mut before.drawn),
            over: std::mem::take(&mut before.over),
            kept: true,
        };
        let (width, w) = (self.width as usize, rect.w as usize);
        for (row, cells) in part.drawn.chunks(w).enumerate() {
            let at = (rect.y as usize + row) * width + rect.x as usize;
            self.cells[at..at + w].copy_from_slice(cells);
        }
        for &(at, cell) in &part.over {
            self.cells[at] = cell;
        }
        self.live.push(part);
        Some(self.live.len() - 1)
    }

    /// Whether the cells of `rect`, which is inside the grid, are `cells`.
    fn cells_are(&self, rect: Rect, cells: &[Cell]) -> bool {
        let (width, w) = (self.width as usize, rect.w as usize);
        cells.len() == w * rect.h.max(0) as usize
            && cells.chunks(w.max(1)).enumerate().all(|(row, want)| {
                let at = (rect.y as usize + row) * width + rect.x as usize;
                self.cells[at..at + w] == *want
            })
    }

    /// The frame is done: find, for each live part, the cells that
    /// something not live drew over it after it. A cell of a later live
    /// part is that part's own.
    pub fn live_seal(&mut self) {
        let width = self.width as usize;
        for index in 0..self.live.len() {
            if std::mem::take(&mut self.live[index].kept) {
                continue;
            }
            let rect = self.live[index].rect;
            let mut over = std::mem::take(&mut self.live[index].over);
            over.clear();
            for (i, drawn) in self.live[index].drawn.iter().enumerate() {
                let (x, y) = (rect.x + (i as i32 % rect.w), rect.y + (i as i32 / rect.w));
                let at = y as usize * width + x as usize;
                if self.cells[at] != *drawn && !self.live[index + 1..].iter().any(|l| l.rect.contains(x, y)) {
                    over.push((at, self.cells[at]));
                }
            }
            self.live[index].over = over;
        }
        if self.live.len() != self.live_before.len() {
            self.live_changed = true;
        }
        self.spare.give(&mut self.live_before);
    }

    /// Take the live parts off the frame, the last drawn first, to draw
    /// them again ([`Grid::live_begin`] in the same order). Returns how
    /// many there were.
    pub fn live_restore(&mut self) -> usize {
        // The parts of the frame before become the ones before; the list
        // they leave, emptied, takes the new ones.
        self.spare.give(&mut self.live_before);
        std::mem::swap(&mut self.live, &mut self.live_before);
        let width = self.width as usize;
        for part in self.live_before.iter().rev() {
            let r = part.rect;
            for row in 0..r.h {
                let at = (r.y + row) as usize * width + r.x as usize;
                let from = (row * r.w) as usize;
                self.cells[at..at + r.w as usize].copy_from_slice(&part.under[from..from + r.w as usize]);
            }
        }
        let count = self.live_before.len();
        self.live_changed = false;
        count
    }

    /// Whether the live parts drawn again since [`Grid::live_restore`]
    /// changed a cell. The cells of the frame are all as before when not.
    pub fn live_changed(&self) -> bool {
        self.live_changed
    }

    /// No live part changed since the frame drawn last: the frame stays as
    /// it is, with its live parts, and there is nothing to send.
    pub fn live_still(&mut self) {
        self.live_changed = false;
    }

    /// Keep a rectangle of cells for pixels, under the name `key`. Over
    /// the text (`under` false) its cells are made blank, in the terminal's
    /// own colours, so that nothing in them breaks the image; under the
    /// text they are left to the view, which goes on drawing them until it
    /// is done ([`Grid::seal_surfaces`]). Returns the surface's index, or
    /// nothing when the rectangle is off the screen.
    pub fn surface(&mut self, key: &str, area: Rect, cell: (u16, u16), under: bool) -> Option<usize> {
        let area = area.intersect(&self.rect());
        if area.w <= 0 || area.h <= 0 {
            return None;
        }
        if !under {
            // Covered by one shown later, a surface already there shows less.
            self.fill(area, area, Some(' '), Style { fg: Some(Color::Default), bg: Some(Color::Default), on: 0, off: 0xff });
        }
        self.surfaces.push(Surface {
            key: key.to_string(),
            rect: area,
            cell,
            under,
            covered: vec![false; (area.w * area.h) as usize],
            ops: Default::default(),
            open: under,
            offset: (0, 0),
            whole: (0, 0),
        });
        Some(self.surfaces.len() - 1)
    }

    /// [`Grid::surface`] for the part of `whole` inside `clip` that is on
    /// the screen, keeping where that part is in the whole.
    pub fn surface_part(&mut self, key: &str, whole: Rect, clip: Rect, cell: (u16, u16), under: bool) -> Option<usize> {
        let index = self.surface(key, whole.intersect(&clip), cell, under)?;
        let s = &mut self.surfaces[index];
        s.offset = (s.rect.x - whole.x, s.rect.y - whole.y);
        if (s.rect.w, s.rect.h) != (whole.w, whole.h) {
            s.whole = (whole.w, whole.h);
        }
        Some(index)
    }

    /// The view that kept the open surfaces is done: what is written over
    /// them from now on (a menu, a floating view) covers them.
    pub fn seal_surfaces(&mut self) {
        for surface in &mut self.surfaces {
            surface.open = false;
        }
    }

    pub fn rect(&self) -> Rect {
        Rect {
            x: 0,
            y: 0,
            w: self.width as i32,
            h: self.height as i32,
        }
    }

    /// Draw text starting at `(x, y)`, keeping inside `clip`. Returns how many
    /// columns the text takes, whether or not all of it was visible.
    pub fn text(&mut self, clip: Rect, x: i32, y: i32, text: &str, style: Style) -> i32 {
        let surfaces = &mut self.surfaces;
        paw_scene::cells::write_text(&mut self.cells, self.width, clip, x, y, text, style, |x, y| cover(surfaces, x, y))
    }

    /// Restyle an area and, when `ch` is given, overwrite its characters.
    pub fn fill(&mut self, clip: Rect, area: Rect, ch: Option<char>, style: Style) {
        let surfaces = &mut self.surfaces;
        paw_scene::cells::write_fill(&mut self.cells, self.width, clip, area, ch, style, |x, y| cover(surfaces, x, y))
    }

    /// The grid as rows of runs of one style each, with the terminal's own
    /// colours given as `fg` and `bg`.
    pub fn runs(&self, fg: (u8, u8, u8), bg: (u8, u8, u8)) -> Vec<Vec<Run>> {
        paw_scene::cells::runs(&self.cells, self.width, fg, bg)
    }
}

/// Mark the cell at `(x, y)` covered in any surface it is in.
fn cover(surfaces: &mut [Surface], x: i32, y: i32) {
    for surface in surfaces {
        let r = surface.rect;
        if !surface.open && r.contains(x, y) {
            surface.covered[((y - r.y) * r.w + (x - r.x)) as usize] = true;
        }
    }
}

/// Named styles, so that views say what something is and themes say how it looks.
#[derive(Default)]
pub(crate) struct Highlights {
    groups: HashMap<String, Highlight>,
    /// Groups as they were defined in 24-bit colour, where the terminal is
    /// shown a nearer form of them: what a window draws.
    full: HashMap<String, Highlight>,
    /// Read the 24-bit forms while set: while a view is drawn for a window.
    pub full_colour: bool,
    /// The number of each group that a view drew with (`id`), so that a
    /// frame passes numbers and not names.
    ids: HashMap<String, StyleId>,
    /// The style of each number, links followed: for the terminal, then in
    /// 24-bit colour. Made again when a group changes.
    resolved: [Vec<Style>; 2],
    /// The name of each number, to make `resolved` again.
    names: Vec<String>,
}

/// The number of a highlight group (`Highlights::id`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct StyleId(pub u32);

pub(crate) enum Highlight {
    Style(Style),
    /// Use whatever another group is set to.
    Link(String),
}

impl Highlights {
    pub(crate) fn set(&mut self, name: &str, highlight: Highlight) {
        self.groups.insert(name.to_string(), highlight);
        self.full.remove(name);
        self.resolve();
    }

    /// Set a group's 24-bit form beside the one the terminal is shown.
    pub(crate) fn set_full(&mut self, name: &str, highlight: Highlight) {
        self.full.insert(name.to_string(), highlight);
        self.resolve();
    }

    /// The number of the group `name`, the same for as long as paw runs. A
    /// group not set yet has one too: it takes the style the group gets.
    pub(crate) fn id(&mut self, name: &str) -> StyleId {
        if let Some(&id) = self.ids.get(name) {
            return id;
        }
        let id = StyleId(self.names.len() as u32);
        self.ids.insert(name.to_string(), id);
        self.names.push(name.to_string());
        let [term, full] = &mut self.resolved;
        term.push(Self::lookup(&self.groups, &self.full, false, name));
        full.push(Self::lookup(&self.groups, &self.full, true, name));
        id
    }

    /// The style of the group numbered `id`, as [`Highlights::get`] gives
    /// it; none for a number that `id` did not give.
    #[inline]
    pub(crate) fn style(&self, id: StyleId) -> Option<Style> {
        self.resolved[usize::from(self.full_colour)].get(id.0 as usize).copied()
    }

    /// Make the style of each number again, after a change of a group.
    fn resolve(&mut self) {
        for (full, styles) in self.resolved.iter_mut().enumerate() {
            styles.clear();
            styles.extend(self.names.iter().map(|name| Self::lookup(&self.groups, &self.full, full == 1, name)));
        }
    }

    /// The style of a group, following links. Unknown groups have no effect.
    pub(crate) fn get(&self, name: &str) -> Style {
        Self::lookup(&self.groups, &self.full, self.full_colour, name)
    }

    fn lookup(
        groups: &HashMap<String, Highlight>,
        full_groups: &HashMap<String, Highlight>,
        full_colour: bool,
        name: &str,
    ) -> Style {
        let mut name = name;
        for _ in 0..8 {
            let full = full_colour.then(|| full_groups.get(name)).flatten();
            match full.or_else(|| groups.get(name)) {
                Some(Highlight::Style(style)) => return *style,
                Some(Highlight::Link(target)) => name = target,
                None => break,
            }
        }
        Style::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rows_become_runs_of_one_style_with_colours_resolved() {
        let mut grid = Grid::new(8, 2);
        let clip = grid.rect();
        let red = Style {
            fg: Some(Color::Rgb(255, 0, 0)),
            ..Style::default()
        };
        grid.text(clip, 0, 0, "ab", red);
        grid.text(clip, 2, 0, "界c", Style { on: REVERSE, ..red });
        let bold_dim = Style {
            fg: Some(Color::Indexed(196)),
            on: BOLD | DIM,
            ..Style::default()
        };
        grid.text(clip, 0, 1, "x", bold_dim);
        let runs = grid.runs((200, 200, 200), (0, 0, 0));
        assert_eq!(runs[0].len(), 3);
        assert_eq!((runs[0][0].text.as_str(), runs[0][0].fg.as_str(), runs[0][0].w), ("ab", "#ff0000", 2));
        // Reversed: the terminal's background in front and red behind; the
        // wide character takes two columns.
        let run = &runs[0][1];
        assert_eq!((run.text.as_str(), run.fg.as_str(), run.bg.as_str()), ("界c", "#000000", "#ff0000"));
        assert_eq!((run.x, run.w), (2, 3));
        assert_eq!((runs[0][2].x, runs[0][2].w, runs[0][2].fg.as_str()), (5, 3, "#c8c8c8"));
        // Indexed 196 is xterm's red, dimmed halfway to the background.
        assert_eq!((runs[1][0].fg.as_str(), runs[1][0].attrs), ("#7f0000", BOLD));
    }

    #[test]
    fn a_live_part_drawn_again_moves_over_what_was_under_it_and_under_what_was_over_it() {
        let mut grid = Grid::new(10, 3);
        let clip = grid.rect();
        let plain = Style::default();
        grid.text(clip, 0, 1, "abcdefghij", plain);
        // A playhead over the row, at column 2, and a float over columns 6
        // to 7 drawn after it.
        let line = Rect { x: 0, y: 1, w: 10, h: 1 };
        let part = grid.live_begin(line).unwrap();
        grid.text(clip, 2, 1, "|", plain);
        grid.live_end(part);
        grid.text(clip, 6, 1, "##", plain);
        grid.live_seal();
        let row = |g: &Grid| g.cells[10..20].iter().map(|c| c.ch).collect::<String>();
        assert_eq!(row(&grid), "ab|def##ij");
        // Drawn again at column 6, under the float, then at column 8.
        for (at, want) in [(6, "abcdef##ij"), (8, "abcdef##|j")] {
            assert_eq!(grid.live_restore(), 1);
            let part = grid.live_begin(line).unwrap();
            grid.text(clip, at, 1, "|", plain);
            grid.live_end(part);
            grid.live_seal();
            assert_eq!(row(&grid), want, "the playhead at {at}");
            assert!(grid.live_changed());
        }
        // The same again: no cell changed.
        grid.live_restore();
        let part = grid.live_begin(line).unwrap();
        grid.text(clip, 8, 1, "|", plain);
        grid.live_end(part);
        grid.live_seal();
        assert!(!grid.live_changed(), "nothing to send");
        // A whole frame starts afresh.
        grid.clear();
        assert!(grid.live.is_empty());
    }

    #[test]
    fn a_live_part_kept_shows_what_it_drew_under_what_was_over_it_until_a_part_before_changes() {
        let mut grid = Grid::new(10, 3);
        let clip = grid.rect();
        let plain = Style::default();
        grid.text(clip, 0, 1, "abcdefghij", plain);
        let line = Rect { x: 0, y: 1, w: 10, h: 1 };
        let meter = Rect { x: 0, y: 1, w: 3, h: 1 };
        let row = |g: &Grid| g.cells[10..20].iter().map(|c| c.ch).collect::<String>();
        // A meter, then a playhead over the same row, then a float.
        let draw = |grid: &mut Grid, level: &str, keep_playhead: bool| -> bool {
            let part = grid.live_begin(meter).unwrap();
            grid.text(clip, 0, 1, level, plain);
            grid.live_end(part);
            let kept = keep_playhead && grid.live_keep(1).is_some();
            if !kept {
                let part = grid.live_begin(line).unwrap();
                grid.text(clip, 5, 1, "|", plain);
                grid.live_end(part);
            }
            kept
        };
        draw(&mut grid, "==", false);
        grid.text(clip, 7, 1, "#", plain);
        grid.live_seal();
        assert_eq!(row(&grid), "==cde|g#ij");
        // The meter as it was: the playhead is kept, the float stays over it.
        grid.live_restore();
        assert!(draw(&mut grid, "==", true), "kept");
        grid.live_seal();
        assert_eq!(row(&grid), "==cde|g#ij");
        assert!(!grid.live_changed(), "nothing to send");
        // The meter falls: the playhead over it must be drawn again.
        grid.live_restore();
        assert!(!draw(&mut grid, "=", true), "drawn again");
        grid.live_seal();
        assert_eq!(row(&grid), "=bcde|g#ij");
        assert!(grid.live_changed());
    }

    #[test]
    fn a_strip_under_the_text_keeps_the_views_cells_and_is_covered_only_after() {
        let mut grid = Grid::new(10, 4);
        let clip = grid.rect();
        let lane = Style { bg: Some(Color::Rgb(1, 2, 3)), ..Style::default() };
        grid.fill(clip, clip, Some(' '), lane);
        let area = Rect { x: 1, y: 1, w: 6, h: 2 };
        grid.surface("curve:1", area, (10, 20), false).unwrap();
        // Over the text: blank, in the terminal's colours.
        assert_eq!(grid.cells[11], Cell::default());
        grid.surfaces.clear();
        grid.fill(clip, clip, Some(' '), lane);
        grid.surface("curve:1", area, (10, 20), true).unwrap();
        assert_eq!(grid.cells[11].bg, Color::Rgb(1, 2, 3), "under the text the cells stay");
        // The view's own cursor and points: drawn, and not covers.
        grid.text(clip, 2, 1, "+", Style::default());
        assert_eq!(grid.cells[12].ch, '+');
        assert!(grid.surfaces[0].covered.iter().all(|c| !c));
        // Once the view is done, a menu over it covers it.
        grid.seal_surfaces();
        grid.text(clip, 3, 2, "ok", Style::default());
        assert_eq!(grid.surfaces[0].covered_runs(), vec![[2, 1, 2]]);
    }

    #[test]
    fn two_strips_side_by_side_are_each_covered_by_what_falls_in_them() {
        let mut grid = Grid::new(10, 4);
        let clip = grid.rect();
        grid.surface("a", Rect { x: 0, y: 0, w: 4, h: 2 }, (10, 20), false).unwrap();
        grid.surface("b", Rect { x: 4, y: 0, w: 4, h: 2 }, (10, 20), false).unwrap();
        grid.text(clip, 3, 1, "xy", Style::default());
        assert_eq!(grid.surfaces[0].covered_runs(), vec![[3, 1, 1]]);
        assert_eq!(grid.surfaces[1].covered_runs(), vec![[0, 1, 1]]);
    }

    #[test]
    fn full_colour_groups_are_read_only_when_asked_for() {
        let mut groups = Highlights::default();
        let style = |fg| Highlight::Style(Style { fg: Some(fg), ..Style::default() });
        groups.set("Normal", style(Color::Indexed(1)));
        groups.set_full("Normal", style(Color::Rgb(1, 2, 3)));
        groups.set("Text", Highlight::Link("Normal".into()));
        assert_eq!(groups.get("Text").fg, Some(Color::Indexed(1)));
        groups.full_colour = true;
        assert_eq!(groups.get("Text").fg, Some(Color::Rgb(1, 2, 3)));
    }
}
