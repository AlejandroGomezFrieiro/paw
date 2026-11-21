//! The windows the kernel draws (a pane of the main area that the window
//! has no drawing of its own for, a view in a window of its own), from
//! their scenes (crates/paw-scene). The kernel pushes what changed of each
//! as it changes (`scene.patch`), and every frame draws from the copy kept
//! here, asking nothing: the cells as text in the window's monospace font,
//! block characters, braille and sextants as rectangles, the pictures as
//! images made again only when their drawing changes, the roles it knows
//! (crate::roles: faders, meters, switches...) as widgets, the meters moved
//! by the live values (`scene.live`). The window tells the kernel how big
//! each window is, in cells (`scene.area`), and passes the pointer on in
//! the same units (`scene.input`), where the view's hit regions give it its
//! meaning. See runtime/lua/paw/scene.tl and docs/reference/protocol.md.

use std::collections::{HashMap, HashSet};

use egui::{Color32, ColorImage, CornerRadius, Id, Pos2, Rect, Shape, Stroke, TextureHandle, Ui, pos2, vec2};
use paw_scene::cells::{BOLD, Run, STRIKE, UNDERLINE};
use paw_scene::{Kind, Node, Patch, Scene};
use serde_json::{Value, json};
use unicode_width::UnicodeWidthChar;

use crate::app::View;
use crate::panes::pointer_events;
use crate::roles;
use crate::theme::{hex, mono, mono_medium};

/// The size of the monospace font cells are drawn in.
pub const MONO_SIZE: f32 = 13.0;

/// The window's cell, in points: a character of its monospace font wide,
/// a row of it high. Views drawn in cells are laid out on it.
pub fn cell(ctx: &egui::Context) -> (f32, f32) {
    let font = mono(MONO_SIZE);
    ctx.fonts_mut(|f| (f.glyph_width(&font, 'M'), f.row_height(&font)))
}

/// A drawing in a scene, and the image made of it.
struct Picture {
    /// Its node's key.
    key: String,
    /// Where it is in units, and the part of it that shows.
    rect: [f32; 4],
    clip: Option<[f32; 4]>,
    under: bool,
    /// The size in pixels it was drawn for.
    px: [f32; 2],
    /// The drawing read, and what its page shows, as a hash.
    drawing: std::sync::Arc<paw_raster::Drawing>,
    page_key: u64,
    /// The page's image, and its size in pixels.
    image: Option<(TextureHandle, [usize; 2])>,
    /// The overlay (what moves over the page: a playhead, a caret), in
    /// pieces that do not touch, each made apart, so that a playhead
    /// moving over a page does not make the page's image or the rest of
    /// the overlay anew.
    over: Vec<Piece>,
}

/// A piece of a drawing's overlay: its items, what they show as a hash, its
/// box in the drawing's pixels, and its image with its size in pixels.
struct Piece {
    items: Vec<paw_raster::Item>,
    key: u64,
    area: [f32; 4],
    image: Option<(TextureHandle, [usize; 2])>,
}

/// The overlay's items in pieces that do not touch (2 pixels apart at
/// least), each in the order drawn.
fn pieces(items: &[paw_raster::Item]) -> Vec<Piece> {
    let mut groups: Vec<([f32; 4], Vec<usize>)> = Vec::new();
    for (i, item) in items.iter().enumerate() {
        let [l, t, r, b] = item.bounds;
        if !(r > l && b > t) {
            continue;
        }
        let mut area = [l - 2.0, t - 2.0, r + 2.0, b + 2.0];
        let mut members = vec![i];
        // Every group it reaches joins it, and the groups those reach.
        loop {
            let Some(at) = groups.iter().position(|(a, _)| a[0] < area[2] && area[0] < a[2] && a[1] < area[3] && area[1] < a[3]) else { break };
            let (a, m) = groups.swap_remove(at);
            area = [area[0].min(a[0]), area[1].min(a[1]), area[2].max(a[2]), area[3].max(a[3])];
            members.extend(m);
        }
        groups.push((area, members));
    }
    groups
        .into_iter()
        .map(|(a, mut members)| {
            members.sort_unstable();
            let items: Vec<paw_raster::Item> = members.iter().map(|&i| items[i].clone()).collect();
            let mut hasher = std::hash::DefaultHasher::new();
            for item in &items {
                std::hash::Hash::hash(&item.key, &mut hasher);
            }
            let (l, t) = ((a[0] + 2.0).floor().max(0.0), (a[1] + 2.0).floor().max(0.0));
            let area = [l, t, (a[2] - 2.0).ceil() - l, (a[3] - 2.0).ceil() - t];
            std::hash::Hash::hash(&area.map(f32::to_bits), &mut hasher);
            Piece { items, key: std::hash::Hasher::finish(&hasher), area, image: None }
        })
        .filter(|p| p.area[2] > 0.0 && p.area[3] > 0.0)
        .collect()
}

/// What the still part of a scene was painted for: its rectangle, its cut,
/// the cell and scale, the roles that moved, and the clips' pictures made.
type StillKey = (Rect, Rect, [f32; 3], Vec<usize>, u64);

/// A window's scene, and what is drawn of it.
#[derive(Default)]
pub struct Shown {
    scene: Scene,
    /// The scene lowered to cells, as rows of runs.
    rows: Vec<Vec<Run>>,
    pictures: Vec<Picture>,
    /// The roles painted here, where they are and what they are cut to, in
    /// units (left, top, right, bottom).
    roles: Vec<(Node, [f64; 4], [f64; 4])>,
    /// The runs and fills drawn over those roles, painted over them again.
    over: Vec<(Node, [f64; 4], [f64; 4])>,
    /// The shapes of the cells' backgrounds and of their text, and where,
    /// on what cell and at what scale they were made.
    shapes: Option<(Vec<Shape>, Vec<Shape>, [f32; 5])>,
    /// The shapes of what is drawn over the roles, each with what it is
    /// cut to, made as the cells' are.
    over_shapes: Option<(Vec<(Rect, Shape)>, [f32; 5])>,
    /// The shapes of what does not move, as last painted, and for what:
    /// where, cut to what, at what cell and scale, with which roles moving.
    still: Option<(StillKey, Vec<egui::epaint::ClippedShape>)>,
}

#[derive(Default)]
pub struct Scenes {
    shown: HashMap<String, Shown>,
    /// The size each window was last said to be, in units.
    told: HashMap<String, [f32; 2]>,
    /// The windows drawn this frame.
    seen: HashSet<String>,
    /// The window the pointer was over last frame, and this frame: the
    /// kernel is told when it leaves one, for the hint it gave there.
    hovered: Option<String>,
    hovering: Option<String>,
    /// Drawings sent by their content key, fetched once.
    blobs: HashMap<String, Value>,
    /// The window's cell, once measured: the kernel is told it then.
    pub cell: Option<(f32, f32)>,
    /// What bound nodes are moved by, as the kernel last sent it.
    pub live: Value,
    /// With `PAW_GUI_STATS`: the patches taken by window, the nodes they
    /// set, and since when.
    pub counted: Option<(HashMap<String, (u64, u64)>, std::time::Instant)>,
}

impl Scenes {
    /// The scenes, counting the patches taken when `count` (`PAW_GUI_STATS`).
    pub fn counting(count: bool) -> Scenes {
        Scenes { counted: count.then(|| (HashMap::new(), std::time::Instant::now())), ..Scenes::default() }
    }

    /// The scene of the window `win`, as drawn.
    pub fn shown_of(&self, win: &str) -> Option<&Shown> {
        self.shown.get(win)
    }

    /// The window's cell, or the size it has before it is measured.
    pub fn cell(&self) -> (f32, f32) {
        self.cell.unwrap_or((7.8, 17.0))
    }
}

/// A colour as a scene writes it.
fn colour(text: &str) -> Color32 {
    hex(text).unwrap_or(Color32::GRAY)
}

/// Block elements, braille and sextants as the parts of their cell they
/// cover (left, top, right, bottom, in fractions of it) and how opaque, so
/// that they fill it and join the next as the terminal shows them.
fn blocks(c: char) -> Option<(Vec<[f32; 4]>, f32)> {
    let u = c as u32;
    let mut parts = Vec::new();
    let mut alpha = 1.0;
    // The quadrants, by bit: upper left, upper right, lower left, lower right.
    const QUADRANTS: [u8; 10] = [0b0100, 0b1000, 0b0001, 0b1101, 0b1001, 0b0111, 0b1011, 0b0010, 0b0110, 0b1110];
    match u {
        0x2580 => parts.push([0.0, 0.0, 1.0, 0.5]),
        0x2581..=0x2588 => parts.push([0.0, 1.0 - (u - 0x2580) as f32 / 8.0, 1.0, 1.0]),
        0x2589..=0x258F => parts.push([0.0, 0.0, (0x2590 - u) as f32 / 8.0, 1.0]),
        0x2590 => parts.push([0.5, 0.0, 1.0, 1.0]),
        0x2591..=0x2593 => {
            alpha = (u - 0x2590) as f32 / 4.0;
            parts.push([0.0, 0.0, 1.0, 1.0]);
        }
        0x2594 => parts.push([0.0, 0.0, 1.0, 0.125]),
        0x2595 => parts.push([0.875, 0.0, 1.0, 1.0]),
        0x2596..=0x259F => {
            let bits = QUADRANTS[(u - 0x2596) as usize];
            for (bit, part) in [[0.0, 0.0, 0.5, 0.5], [0.5, 0.0, 1.0, 0.5], [0.0, 0.5, 0.5, 1.0], [0.5, 0.5, 1.0, 1.0]].into_iter().enumerate() {
                if bits & (1 << bit) != 0 {
                    parts.push(part);
                }
            }
        }
        0x2800..=0x28FF => {
            // Dots in two columns of four; the bits count down the first
            // column's three, the second's three, then the bottom two.
            const ROW: [f32; 8] = [0.0, 1.0, 2.0, 0.0, 1.0, 2.0, 3.0, 3.0];
            const COLUMN: [f32; 8] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0];
            for bit in 0..8 {
                if (u - 0x2800) & (1 << bit) != 0 {
                    let (x, y) = ((COLUMN[bit] + 0.5) / 2.0, (ROW[bit] + 0.5) / 4.0);
                    parts.push([x - 0.12, y - 0.065, x + 0.12, y + 0.065]);
                }
            }
        }
        0x1FB00..=0x1FB3B => {
            // Six parts, a half wide and a third tall; the full left and
            // right halves are characters of their own, left out here.
            let mut bits = u - 0x1FB00 + 1;
            if bits >= 21 {
                bits += 1;
            }
            if bits >= 42 {
                bits += 1;
            }
            for bit in 0..6 {
                if bits & (1 << bit) != 0 {
                    let (x, y) = ((bit % 2) as f32 / 2.0, (bit / 2) as f32 / 3.0);
                    parts.push([x, y, x + 0.5, y + 1.0 / 3.0]);
                }
            }
        }
        _ => return None,
    }
    Some((parts, alpha))
}

impl Shown {
    /// Take in a patch, and what it changes of the cells and the pictures.
    fn take(&mut self, patch: &Patch, blobs: &HashMap<String, Value>) {
        // A patch that only draws pictures anew where they were (a canvas
        // view's playhead, as the song plays) leaves the cells and the
        // roles as they are.
        let pictures_only = !patch.full
            && patch.size.is_none()
            && patch.root.is_none()
            && patch.drop.is_empty()
            && patch.colors.is_none()
            && patch.cursor.is_none()
            && !patch.set.is_empty()
            && patch.set.iter().all(|new| {
                matches!(new.kind, Kind::Picture(_))
                    && self.scene.nodes.get(&new.key).is_some_and(|old| matches!(old.kind, Kind::Picture(_)) && old.rect == new.rect && old.clip == new.clip && old.kids == new.kids)
            });
        self.scene.apply(patch);
        if pictures_only {
            self.take_pictures(blobs);
            self.still = None;
            return;
        }
        self.over = self.scene.over_roles(&|role| roles::KNOWN.contains(&role));
        // What is drawn over a role is painted over it; in the cells under
        // the roles it would be painted twice.
        let (fg, bg) = self.scene.colors();
        let mut under = self.scene.clone();
        for (node, _, _) in &self.over {
            if let Some(n) = under.nodes.get_mut(&node.key) {
                n.kind = Kind::Group;
            }
        }
        self.rows = under.to_cells().runs(fg, bg);
        self.take_pictures(blobs);
        let mut placed = Vec::new();
        self.scene.placed(&mut |node, rect, cut| {
            if let Kind::Role { role, .. } = &node.kind
                && roles::KNOWN.contains(&role.as_str())
            {
                placed.push((node.clone(), rect, cut));
            }
        });
        self.roles = placed;
        self.shapes = None;
        self.over_shapes = None;
        self.still = None;
    }

    /// The scene's pictures, each keeping its image while its drawing is
    /// the same.
    fn take_pictures(&mut self, blobs: &HashMap<String, Value>) {
        let mut before: HashMap<String, Picture> = self.pictures.drain(..).map(|p| (p.key.clone(), p)).collect();
        let mut pictures = Vec::new();
        self.scene.walk(&mut |node| {
            let Kind::Picture(picture) = &node.kind else { return };
            let ops = match (&picture.ops, &picture.blob) {
                (Some(ops), _) => ops.clone(),
                (None, Some(key)) => blobs.get(key).cloned().unwrap_or(Value::Null),
                _ => Value::Null,
            };
            let drawing = paw_raster::Drawing::parse(&ops);
            let keys = |items: &[paw_raster::Item]| {
                let mut hasher = std::hash::DefaultHasher::new();
                for item in items {
                    std::hash::Hash::hash(&item.key, &mut hasher);
                }
                std::hash::Hasher::finish(&hasher)
            };
            let page_key = keys(&drawing.page);
            // A page that did not change keeps its image; a piece of the
            // overlay too.
            let old = before.remove(&node.key).filter(|p| p.rect == node.rect && p.px == picture.px);
            let image = old.as_ref().filter(|p| p.page_key == page_key).and_then(|p| p.image.clone());
            let mut over = pieces(&drawing.overlay);
            if let Some(old) = old {
                let mut kept: HashMap<u64, (TextureHandle, [usize; 2])> = old.over.into_iter().filter_map(|p| Some((p.key, p.image?))).collect();
                for piece in &mut over {
                    piece.image = kept.remove(&piece.key);
                }
            }
            pictures.push(Picture {
                key: node.key.clone(),
                rect: node.rect,
                clip: node.clip,
                under: picture.under,
                px: picture.px,
                drawing: std::sync::Arc::new(drawing),
                page_key,
                image,
                over,
            });
        });
        self.pictures = pictures;
    }

    /// The shapes of the runs and fills a view drew over the roles painted
    /// here, to paint over them as a terminal shows them, each with what it
    /// is cut to: text and its background where it has one; a fill that
    /// only restyles (the selection, the cursor) a tint, so that what it
    /// covers still shows through.
    fn over_shapes(&self, ctx: &egui::Context, at: Pos2, (cw, ch): (f32, f32)) -> Vec<(Rect, Shape)> {
        let mut out = Vec::new();
        let (fg, bg) = self.scene.colors();
        let colour = |c: Option<paw_scene::cells::Color>, or: (u8, u8, u8)| {
            c.map(|c| {
                let (r, g, b) = paw_scene::cells::rgb(c, or);
                Color32::from_rgb(r, g, b)
            })
        };
        for (node, rect, cut) in &self.over {
            let cells = |l: f64, t: f64, r: f64, b: f64| {
                Rect::from_min_max(pos2(at.x + l.floor() as f32 * cw, at.y + t.floor() as f32 * ch), pos2(at.x + r.floor() as f32 * cw, at.y + b.floor() as f32 * ch))
            };
            let shown = cells(rect[0], rect[1], rect[2], rect[3]);
            let cut = cells(cut[0], cut[1], cut[2], cut[3]);
            let back = colour(node.style.bg, bg);
            let ink = colour(node.style.fg, fg).unwrap_or(Color32::from_rgb(fg.0, fg.1, fg.2));
            let font = if node.style.on & BOLD != 0 { mono_medium(MONO_SIZE) } else { mono(MONO_SIZE) };
            let text = match &node.kind {
                Kind::Run { text } => Some(text.clone()),
                Kind::Fill { ch: Some(c) } => Some(c.to_string().repeat(shown.width().div_euclid(cw).max(1.0) as usize)),
                Kind::Fill { ch: None } => {
                    if let Some(back) = back {
                        out.push((cut, Shape::rect_filled(shown, CornerRadius::ZERO, back.gamma_multiply(0.45))));
                    }
                    None
                }
                _ => None,
            };
            let Some(text) = text else { continue };
            if let Some(back) = back {
                out.push((cut, Shape::rect_filled(shown, CornerRadius::ZERO, back)));
            }
            if text.trim().is_empty() {
                continue;
            }
            for row in 0..(shown.height() / ch).round().max(1.0) as usize {
                let galley = ctx.fonts_mut(|f| f.layout_no_wrap(text.clone(), font.clone(), ink));
                out.push((cut, Shape::galley(pos2(shown.left(), shown.top() + row as f32 * ch), galley, ink)));
            }
        }
        out
    }

    /// The shapes of the cells' backgrounds and text, from `at`.
    fn shapes(&self, ctx: &egui::Context, at: Pos2, (cw, ch): (f32, f32)) -> (Vec<Shape>, Vec<Shape>) {
        let (mut back, mut text) = (Vec::new(), Vec::new());
        let bg = self.scene.bg.as_str();
        let cell_rect = |x: f32, y: f32, w: f32| Rect::from_min_size(pos2(at.x + x * cw, at.y + y * ch), vec2(w * cw, ch));
        // The grounds the roles paint over all of (a row of a timeline, a
        // header): the cells' backgrounds under them are not drawn, each
        // pixel drawn costs.
        let grounds: Vec<[f64; 4]> = self
            .roles
            .iter()
            .filter(|(node, _, _)| matches!(&node.kind, Kind::Role { role, .. } if roles::OPAQUE.contains(&role.as_str())))
            .map(|(_, r, c)| [r[0].max(c[0]), r[1].max(c[1]), r[2].min(c[2]), r[3].min(c[3])])
            .collect();
        let hidden = |x: f64, y: f64, w: f64| grounds.iter().any(|g| g[0] <= x && g[1] <= y && g[2] >= x + w && g[3] >= y + 1.0);
        ctx.fonts_mut(|fonts| {
            for (y, row) in self.rows.iter().enumerate() {
                let y = y as f32;
                for run in row {
                    if run.bg != bg && !hidden(run.x as f64, y as f64, run.w as f64) {
                        back.push(Shape::rect_filled(cell_rect(run.x as f32, y, run.w as f32), CornerRadius::ZERO, colour(&run.bg)));
                    }
                    let fg = colour(&run.fg);
                    let font = if run.attrs & BOLD != 0 { mono_medium(MONO_SIZE) } else { mono(MONO_SIZE) };
                    // Characters of the font go together as one piece of
                    // text (`piece`, from column `from`); any other is drawn
                    // by itself, at its column.
                    let (mut piece, mut from, mut col) = (String::new(), run.x as f32, run.x as f32);
                    for c in run.text.chars().chain(['\n']) {
                        let width = if c == '\n' { 0.0 } else { c.width().unwrap_or(0) as f32 };
                        let joins = width == 1.0 && blocks(c).is_none() && (fonts.glyph_width(&font, c) - cw).abs() < 0.5;
                        if joins {
                            if piece.is_empty() {
                                from = col;
                            }
                            piece.push(c);
                            col += width;
                            continue;
                        }
                        if !piece.trim().is_empty() {
                            let galley = fonts.layout_no_wrap(std::mem::take(&mut piece), font.clone(), fg);
                            text.push(Shape::galley(cell_rect(from, y, 1.0).min, galley, fg));
                        }
                        piece.clear();
                        if width == 0.0 {
                            continue;
                        }
                        if let Some((parts, alpha)) = blocks(c) {
                            let cell = cell_rect(col, y, 1.0);
                            for [l, t, r, b] in parts {
                                let part = Rect::from_min_max(cell.lerp_inside(vec2(l, t)), cell.lerp_inside(vec2(r, b)));
                                text.push(Shape::rect_filled(part, CornerRadius::ZERO, fg.gamma_multiply(alpha)));
                            }
                        } else if !c.is_whitespace() {
                            let galley = fonts.layout_no_wrap(c.to_string(), font.clone(), fg);
                            text.push(Shape::galley(cell_rect(col, y, width).min, galley, fg));
                        }
                        col += width;
                    }
                    let line = |frac: f32| {
                        let r = cell_rect(run.x as f32, y, run.w as f32);
                        Shape::hline(r.x_range(), r.top() + r.height() * frac, Stroke::new(1.0, fg))
                    };
                    if run.attrs & UNDERLINE != 0 {
                        text.push(line(0.92));
                    }
                    if run.attrs & STRIKE != 0 {
                        text.push(line(0.5));
                    }
                }
            }
        });
        (back, text)
    }

    /// Draw the window's scene over `rect`, cut to `clip`; `id` is the
    /// window's. What moves (the roles bound to live values and the one
    /// under the pointer) is drawn over the rest. The window draws a frame
    /// again only where its shapes changed (crate::damage), so what does
    /// not move costs no drawing.
    fn draw(&mut self, ui: &Ui, id: &str, rect: Rect, clip: Rect, cell: (f32, f32), live: &Value, parts: &mut crate::live::Parts) {
        let painter = ui.painter().with_clip_rect(clip.intersect(ui.clip_rect()));
        let ppp = ui.ctx().pixels_per_point();
        // What moves: the roles bound to live values, and the one under
        // the pointer.
        let moving: Vec<usize> = (0..self.roles.len())
            .filter(|&i| {
                let (node, at, _) = &self.roles[i];
                node.bind.is_some() || ui.rect_contains_pointer(roles::rect_of(*at, rect.min, cell))
            })
            .collect();
        // The rest is painted once, and its shapes are given again while
        // nothing of it changes: no layout, no painting of roles.
        let still_key = (rect, painter.clip_rect(), [cell.0, cell.1, ppp], moving.clone(), crate::timeline::pictures_made());
        if self.still.as_ref().is_none_or(|(key, _)| *key != still_key) {
            let kept = egui::LayerId::new(painter.layer_id().order, Id::unique(("scene-still", id)));
            let still = egui::Painter::new(ui.ctx().clone(), kept, painter.clip_rect());
            self.paint_still(ui, &still, id, rect, cell, live, &moving);
            let shapes = ui.ctx().graphics_mut(|g| std::mem::take(g.entry(kept)));
            self.still = Some((still_key, shapes.all_entries().cloned().collect()));
        } else {
            // What it says to a reader of the window, as when painted, and
            // the clips' pictures it shows, kept.
            for (i, (node, at, _)) in self.roles.iter().enumerate() {
                if !moving.contains(&i) {
                    roles::name(ui, Id::unique(("scene-role", id, &node.key)), node, roles::rect_of(*at, rect.min, cell));
                    crate::timeline::keep_picture(node);
                }
            }
        }
        if let Some((_, shapes)) = &self.still {
            ui.ctx().graphics_mut(|g| {
                let list = g.entry(painter.layer_id());
                for shape in shapes {
                    list.add(shape.clip_rect, shape.shape.clone());
                }
            });
        }
        for i in moving {
            // A role the live values move is a live part: painted again by
            // itself while only they change (crate::live).
            let (node, at, _) = &self.roles[i];
            let part = node.bind.is_some().then(|| {
                let under = ui.rect_contains_pointer(roles::rect_of(*at, rect.min, cell));
                parts.begin(&painter, crate::live::Part::Role { win: id.to_string(), index: i, from: rect.min, cell, under })
            });
            self.role(ui, &painter, id, i, rect.min, cell, live);
            if let Some(n) = part {
                parts.end(&painter, n);
            }
        }
    }

    /// Paint the role `i`, which the live values move, again with
    /// `painter` as `role` painted it, with no `Ui`: `under` says whether
    /// the pointer was over it.
    pub fn role_live(&self, painter: &egui::Painter, i: usize, from: Pos2, cell: (f32, f32), live: &Value, under: bool) {
        let Some((node, at, cut)) = self.roles.get(i) else { return };
        let (cut, at) = (roles::rect_of(*cut, from, cell), roles::rect_of(*at, from, cell));
        let role_painter = if cut.contains_rect(at) { painter.clone() } else { painter.with_clip_rect(cut.intersect(painter.clip_rect())) };
        roles::paint_live(&role_painter, node, at, cell, live, under);
    }

    /// Paint what does not move of the scene with `still`: the ground, the
    /// cells, the pictures, the roles but those `moving`, what is drawn
    /// over them, the cursor.
    #[allow(clippy::too_many_arguments)]
    fn paint_still(&mut self, ui: &Ui, still: &egui::Painter, id: &str, rect: Rect, cell: (f32, f32), live: &Value, moving: &[usize]) {
        still.rect_filled(rect, CornerRadius::ZERO, colour(&self.scene.bg));
        let ppp = ui.ctx().pixels_per_point();
        let key = [rect.min.x, rect.min.y, cell.0, cell.1, ppp];
        if self.shapes.as_ref().is_none_or(|s| s.2 != key) {
            let (back, text) = self.shapes(ui.ctx(), rect.min, cell);
            self.shapes = Some((back, text, key));
        }
        let Some((back, text, _)) = &self.shapes else { return };
        still.extend(back.iter().cloned());
        let text = text.clone();
        self.pictures(ui, still, rect.min, cell, true);
        still.extend(text);
        for i in 0..self.roles.len() {
            if !moving.contains(&i) {
                self.role(ui, still, id, i, rect.min, cell, live);
            }
        }
        if self.over_shapes.as_ref().is_none_or(|s| s.1 != key) {
            self.over_shapes = Some((self.over_shapes(ui.ctx(), rect.min, cell), key));
        }
        if let Some((over, _)) = &self.over_shapes {
            for (cut, shape) in over {
                if cut.contains_rect(shape.visual_bounding_rect()) {
                    still.add(shape.clone());
                } else {
                    still.with_clip_rect(cut.intersect(still.clip_rect())).add(shape.clone());
                }
            }
        }
        self.pictures(ui, still, rect.min, cell, false);
        if let Some([x, y]) = self.scene.cursor {
            let bar = Rect::from_min_size(pos2(rect.min.x + x * cell.0, rect.min.y + y * cell.1), vec2(2.0, cell.1));
            still.rect_filled(bar, CornerRadius::ZERO, colour(&self.scene.fg));
        }
    }

    /// Paint the role `i` of the scene with `painter`, cut as it is.
    #[allow(clippy::too_many_arguments)]
    fn role(&self, ui: &Ui, painter: &egui::Painter, id: &str, i: usize, from: Pos2, cell: (f32, f32), live: &Value) {
        let (node, at, cut) = &self.roles[i];
        let (cut, at) = (roles::rect_of(*cut, from, cell), roles::rect_of(*at, from, cell));
        // A role that shows whole is painted with the window's own cut:
        // shapes of one cut are drawn together, each cut costs a draw.
        let role_painter = if cut.contains_rect(at) { painter.clone() } else { painter.with_clip_rect(cut.intersect(painter.clip_rect())) };
        let salt = Id::unique(("scene-role", id, &node.key));
        roles::paint(ui, &role_painter, salt, node, at, cell, live);
    }

    /// Draw the pictures under the cells' text, or those over it, making
    /// the image of any that has none at the size it is shown at.
    fn pictures(&mut self, ui: &Ui, painter: &egui::Painter, at: Pos2, (cw, ch): (f32, f32), under: bool) {
        let ppp = ui.ctx().pixels_per_point();
        let units = |r: [f32; 4]| Rect::from_min_size(pos2(at.x + r[0] * cw, at.y + r[1] * ch), vec2(r[2] * cw, r[3] * ch));
        for p in self.pictures.iter_mut().filter(|p| p.under == under) {
            let rect = units(p.rect);
            let size = [(rect.width() * ppp).round().max(1.0) as usize, (rect.height() * ppp).round().max(1.0) as usize];
            // The drawing's pixels to the image's: the drawing fills it.
            let scale = size[0] as f32 / p.px[0].max(1.0);
            if p.image.as_ref().is_none_or(|(_, made)| *made != size) {
                let at = tiny_skia::Transform::from_scale(scale, scale);
                let texture = ui.ctx().load_texture("scene-picture", raster(size, &p.drawing.page, at), egui::TextureOptions::LINEAR);
                p.image = Some((texture, size));
            }
            // The overlay's pieces, each in an image of its own the size
            // of its box.
            for piece in &mut p.over {
                let b = piece.area;
                let made = [(b[2] * scale).ceil().max(1.0) as usize, (b[3] * scale).ceil().max(1.0) as usize];
                if piece.image.as_ref().is_none_or(|(_, size)| *size != made) {
                    let at = tiny_skia::Transform::from_row(scale, 0.0, 0.0, scale, -b[0] * scale, -b[1] * scale);
                    let texture = ui.ctx().load_texture("scene-overlay", raster(made, &piece.items, at), egui::TextureOptions::LINEAR);
                    piece.image = Some((texture, made));
                }
            }
            let shown = p.clip.map_or(painter.clip_rect(), |c| units(c).intersect(painter.clip_rect()));
            let whole = Rect::from_min_max(Pos2::ZERO, pos2(1.0, 1.0));
            if let Some((texture, _)) = &p.image {
                painter.with_clip_rect(shown).image(texture.id(), rect, whole, Color32::WHITE);
            }
            for piece in &p.over {
                let Some((texture, made)) = &piece.image else { continue };
                // Its pixels are the page's: from the box's corner, as big.
                let corner = rect.min + vec2(piece.area[0] * scale, piece.area[1] * scale) / ppp;
                let over = Rect::from_min_size(corner, vec2(made[0] as f32, made[1] as f32) / ppp);
                painter.with_clip_rect(shown).image(texture.id(), over, whole, Color32::WHITE);
            }
        }
    }
}

/// Some items of a drawing on an image of `size` pixels, placed by `at`.
fn raster(size: [usize; 2], items: &[paw_raster::Item], at: tiny_skia::Transform) -> ColorImage {
    match tiny_skia::Pixmap::new(size[0] as u32, size[1] as u32) {
        Some(mut pixmap) => {
            paw_raster::paint_with(&mut pixmap, items, at);
            ColorImage::from_rgba_premultiplied(size, pixmap.data())
        }
        None => ColorImage::new(size, vec![Color32::TRANSPARENT; size[0] * size[1]]),
    }
}

impl View {
    /// Watch the scenes of this window's seat from the first frame, when
    /// the window's cell can be measured.
    pub fn scenes_watch(&mut self, ctx: &egui::Context) {
        if self.scenes.cell.is_some() {
            return;
        }
        let (w, h) = cell(ctx);
        self.scenes.cell = Some((w, h));
        // The roles it paints come without their cells; the meters move
        // with the live values.
        let watched = self.k.borrow_mut().call("scene.watch", json!([{ "cell": { "w": w, "h": h }, "roles": roles::KNOWN, "live": true }]));
        if let Err(err) = watched {
            self.show(&format!("{err:#}"), true);
        }
    }

    /// Take in what the kernel pushed of the scenes, fetching the drawings
    /// sent by their key that are not here yet.
    pub fn scene_patches(&mut self) {
        if let Some(live) = self.k.borrow_mut().live() {
            self.scenes.live = live;
            self.repaint = true;
        }
        let patches = self.k.borrow_mut().patches();
        self.take_patches(patches);
    }

    /// Take in patches of the scenes.
    pub fn take_patches(&mut self, patches: Vec<Value>) {
        for patch in patches {
            let Ok(patch) = serde_json::from_value::<Patch>(patch) else { continue };
            // What comes for a window after it went is of no use: a window
            // shown again is sent its whole scene.
            if !patch.full && !self.scenes.shown.contains_key(&patch.win) {
                continue;
            }
            for node in &patch.set {
                if let Kind::Picture(paw_scene::Picture { blob: Some(key), .. }) = &node.kind
                    && !self.scenes.blobs.contains_key(key)
                {
                    let ops = self.k.borrow_mut().call("scene.blob", json!([key])).unwrap_or(Value::Null);
                    self.scenes.blobs.insert(key.clone(), ops);
                }
            }
            let shown = self.scenes.shown.entry(patch.win.clone()).or_default();
            shown.take(&patch, &self.scenes.blobs);
            if let Some((counts, since)) = &mut self.scenes.counted {
                let count = counts.entry(patch.win.clone()).or_default();
                count.0 += 1;
                count.1 += patch.set.len() as u64;
                if since.elapsed().as_secs() >= 10 {
                    let mut all: Vec<_> = counts.drain().collect();
                    all.sort();
                    eprintln!("paw-gui: stats: scene patches (window: patches, nodes set) {all:?}");
                    *since = std::time::Instant::now();
                }
            }
            self.repaint = true;
        }
    }

    /// A window the kernel draws, over `rect` and cut to `clip`, named as
    /// the kernel names it (`3`, `view:undotree`): its size said when it
    /// changes, its scene drawn, and the pointer over it passed on.
    pub fn scene(&mut self, ui: &Ui, id: &str, rect: Rect, clip: Rect) {
        let cell = self.scenes.cell();
        self.scenes.seen.insert(id.to_string());
        if ui.rect_contains_pointer(clip) {
            self.scenes.hovering = Some(id.to_string());
            // The shape the view gives the pointer there (an edge to drag).
            match self.s.modal["pointer"].as_str() {
                Some("resize_h") => ui.ctx().set_cursor_icon(egui::CursorIcon::ResizeHorizontal),
                Some("resize_v") => ui.ctx().set_cursor_icon(egui::CursorIcon::ResizeVertical),
                _ => {}
            }
        }
        let size = [rect.width().max(0.0) / cell.0, rect.height().max(0.0) / cell.1];
        if self.scenes.told.get(id) != Some(&size) {
            self.scenes.told.insert(id.to_string(), size);
            self.call_later("scene.area", json!([id, size[0], size[1]]));
        }
        if let Some(shown) = self.scenes.shown.get_mut(id) {
            shown.draw(ui, id, rect, clip, cell, &self.scenes.live, &mut self.live);
        }
        let pointer = Id::unique(("scene-pointer", id));
        // Whether the press that a release ends was in this window.
        let pressed_here = ui.data(|d| d.get_temp::<bool>(pointer)).unwrap_or(false);
        for mut event in pointer_events(ui, rect, pointer) {
            event["x"] = json!(event["x"].as_f64().unwrap_or(0.0) / cell.0 as f64);
            event["y"] = json!(event["y"].as_f64().unwrap_or(0.0) / cell.1 as f64);
            if !pressed_here && event["kind"] == "up" && self.drop_clip(&mut event) {
                self.call_later("scene.input", json!([id, event]));
                continue;
            }
            self.call_later("scene.input", json!([id, event]));
        }
    }

    /// A release over a window other than the one pressed: if the drag
    /// there moves a clip (from the arrange view), the drag ends without
    /// moving it and the event becomes a drop of the clip on this window's
    /// view (`kind = "drop"`, `clip`), which takes it if it can (a view's
    /// `on_drop`). True when the event was that.
    fn drop_clip(&mut self, event: &mut Value) -> bool {
        // The press, in a window drawn before this one, may be in this
        // frame too (a loaded machine draws few): it goes to the kernel
        // first, which makes the gesture; its release stays queued.
        self.flush_before_release();
        let Some(clip) = self.ask("local g = paw.mouse.gesture(); return g and g.clip", json!([])).as_i64() else {
            return false;
        };
        // At once, not at the end of the frame: the window that has the
        // press may have queued its release already, which must not move it.
        self.ask("paw.mouse.forget(); paw.api.ui_redraw()", json!([]));
        event["kind"] = json!("drop");
        event["clip"] = json!(clip);
        true
    }

    /// At the end of a frame: the windows not drawn in it are gone, and
    /// the kernel is told (a size of nothing), so that it keeps nothing of
    /// them either.
    pub fn scenes_done(&mut self) {
        let hovering = self.scenes.hovering.take();
        if let Some(left) = std::mem::replace(&mut self.scenes.hovered, hovering.clone())
            && Some(&left) != hovering.as_ref()
        {
            self.call_later("scene.input", json!([left, { "kind": "leave" }]));
        }
        let seen = std::mem::take(&mut self.scenes.seen);
        let gone: Vec<String> = self.scenes.told.keys().filter(|id| !seen.contains(*id)).cloned().collect();
        for id in gone {
            self.scenes.told.remove(&id);
            self.scenes.shown.remove(&id);
            self.call_later("scene.area", json!([id, 0, 0]));
        }
        let named: HashSet<&String> = self
            .scenes
            .shown
            .values()
            .flat_map(|s| s.scene.nodes.values())
            .filter_map(|n| match &n.kind {
                Kind::Picture(paw_scene::Picture { blob: Some(key), .. }) => Some(key),
                _ => None,
            })
            .collect();
        let keep: HashSet<String> = named.into_iter().cloned().collect();
        self.scenes.blobs.retain(|key, _| keep.contains(key));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_patch_that_only_draws_a_picture_anew_keeps_the_cells_laid_out() {
        let picture = |ops: Value| Node::new("p", Kind::Picture(paw_scene::Picture { ops: Some(ops), blob: None, px: [40.0, 20.0], under: false }), [0.0, 0.0, 4.0, 2.0]);
        let run = |text: &str| Node::new("r", Kind::Run { text: text.into() }, [0.0, 1.0, 4.0, 1.0]);
        let mut shown = Shown::default();
        let blobs = HashMap::new();
        let full = Patch { win: "1".into(), rev: 1, full: true, size: Some([10.0, 2.0]), root: Some(vec!["r".into(), "p".into()]), set: vec![run("abc"), picture(json!([["r", 0, 0, 10, 10, "#ff0000", "", 1, 0]]))], ..Patch::default() };
        shown.take(&full, &blobs);
        assert_eq!(shown.rows.len(), 2);
        let before = shown.pictures[0].page_key;
        // As drawn once: the shapes of the cells kept.
        shown.shapes = Some((Vec::new(), Vec::new(), [0.0; 5]));
        let playhead = Patch { win: "1".into(), rev: 2, set: vec![picture(json!([["r", 0, 0, 10, 10, "#00ff00", "", 1, 0]]))], ..Patch::default() };
        shown.take(&playhead, &blobs);
        assert!(shown.shapes.is_some(), "the cells are not laid out again");
        assert_ne!(shown.pictures[0].page_key, before, "the picture is new");
        let text = Patch { win: "1".into(), rev: 3, set: vec![run("abd")], ..Patch::default() };
        shown.take(&text, &blobs);
        assert!(shown.shapes.is_none(), "a run changed: the cells are laid out again");
    }

    #[test]
    fn an_overlay_is_cut_into_pieces_apart_so_a_moving_playhead_is_its_own() {
        let ops = |playhead: f32| {
            json!([
                ["r", 0, 0, 400, 300, "#ffffff", "", 1, 0],
                ["layer", "playhead"],
                ["r", playhead, 40, 2, 200, "#ff8800", "", 1, 0],
                // The toolbar: two buttons side by side, far from the staff.
                ["r", 10, 270, 30, 20, "#333333", "", 1, 0],
                ["r", 41, 270, 30, 20, "#333333", "", 1, 0]
            ])
        };
        let (a, b) = (paw_raster::Drawing::parse(&ops(100.0)), paw_raster::Drawing::parse(&ops(120.0)));
        assert_eq!(a.page.len(), 1);
        let (pa, pb) = (pieces(&a.overlay), pieces(&b.overlay));
        assert_eq!(pa.len(), 2, "the playhead, and the toolbar's buttons together");
        let toolbar = |p: &[Piece]| p.iter().find(|p| p.items.len() == 2).map(|p| (p.key, p.area));
        assert_eq!(toolbar(&pa), toolbar(&pb), "the toolbar did not move: its image is kept");
        let head = |p: &[Piece]| p.iter().find(|p| p.items.len() == 1).map(|p| p.key);
        assert_ne!(head(&pa), head(&pb));
        assert_eq!(pa.iter().find(|p| p.items.len() == 1).unwrap().area, [100.0, 40.0, 2.0, 200.0]);
    }

    #[test]
    fn eighth_blocks_fill_from_the_bottom_and_quadrants_are_their_corners() {
        assert_eq!(blocks('▂').unwrap().0, vec![[0.0, 0.75, 1.0, 1.0]]);
        assert_eq!(blocks('█').unwrap().0, vec![[0.0, 0.0, 1.0, 1.0]]);
        assert_eq!(blocks('▎').unwrap().0, vec![[0.0, 0.0, 0.25, 1.0]]);
        assert_eq!(blocks('▚').unwrap().0, vec![[0.0, 0.0, 0.5, 0.5], [0.5, 0.5, 1.0, 1.0]]);
        assert_eq!(blocks('▒').unwrap().1, 0.5);
        // Braille: the full cell has eight dots, the first at the top left.
        let (dots, _) = blocks('⣿').unwrap();
        assert_eq!(dots.len(), 8);
        let (one, _) = blocks('⠁').unwrap();
        assert!(one[0][0] < 0.5 && one[0][1] < 0.25);
        assert!(blocks('a').is_none() && blocks('─').is_none());
    }
}
