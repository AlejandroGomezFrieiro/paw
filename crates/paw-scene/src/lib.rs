//! The scene: what one window of a view shows, for every frontend.
//!
//! A scene is a tree of nodes, each with a rectangle in **cell units** (a
//! terminal's cells; a window's cell of its monospace font) relative to its
//! parent, in drawing order. The kernel builds it as a view draws
//! (`paw-core`'s `scene` module), keeps it, and sends a frontend what changed
//! since it last did as a [`Patch`]; the frontend applies the patch to its
//! copy and draws that. Both sides find what is under the pointer with
//! [`Scene::hit`], and [`Scene::to_cells`] lowers a scene to the cells a
//! terminal shows. See docs/reference/protocol.md, "Scenes".
//!
//! Nodes:
//!
//! - `run`: text in one style along a row (what `buf:text` writes);
//! - `fill`: a rectangle restyled, and its characters overwritten when it
//!   has one (`buf:fill`);
//! - `picture`: a drawing (`paw.canvas` operations) over its rectangle, in
//!   pixels of a size it says, under the cells or over them;
//! - `group`: its kids, placed from its corner and cut to it;
//! - `plane`: its kids, placed in a domain of its own (beats along x and
//!   pitch along y, say), mapped to units by an [`Axis`] each way;
//! - a role (`clip`, `fader`...): a named element over its rectangle,
//!   with its look's data in `props`; a frontend that does not know the
//!   role draws its kids, the role's cells.
//!
//! Any node may be a hit region (`hit`) and be bound to a live value
//! (`bind`) a frontend moves without a new scene.

pub mod cells;
pub mod color;
pub mod props;

use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize, Serializer};
use serde_json::Value;

use cells::{Cells, Color, Rect, Style};

/// A rectangle in units: x, y, width, height.
pub type Units = [f32; 4];

/// Whole numbers go on the wire without a decimal point.
fn short<S: Serializer>(rect: &Units, s: S) -> Result<S::Ok, S::Error> {
    let numbers: Vec<Value> = rect.iter().map(|v| number(*v as f64)).collect();
    numbers.serialize(s)
}

fn short_opt<S: Serializer>(rect: &Option<Units>, s: S) -> Result<S::Ok, S::Error> {
    match rect {
        Some(rect) => short(rect, s),
        None => s.serialize_none(),
    }
}

fn number(v: f64) -> Value {
    if v.fract() == 0.0 && v.abs() < 1e15 { Value::from(v as i64) } else { Value::from(v) }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Node {
    /// Its name, unique in the scene: what it is kept and diffed by.
    #[serde(rename = "k")]
    pub key: String,
    #[serde(flatten)]
    pub kind: Kind,
    /// Where it is, in units of its parent's space.
    #[serde(rename = "r", serialize_with = "short")]
    pub rect: Units,
    /// What it is cut to, in its parent's space; its parent's cut without.
    #[serde(default, skip_serializing_if = "Option::is_none", serialize_with = "short_opt")]
    pub clip: Option<Units>,
    #[serde(rename = "s", default, skip_serializing_if = "Style::is_plain")]
    pub style: Style,
    /// Makes its rectangle a hit region: what a press there is on.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hit: Option<Value>,
    /// A live value the frontend moves it by (`position`, `meter:12`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bind: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub kids: Vec<String>,
}

impl Node {
    pub fn new(key: impl Into<String>, kind: Kind, rect: Units) -> Node {
        Node { key: key.into(), kind, rect, clip: None, style: Style::default(), hit: None, bind: None, kids: Vec::new() }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "lowercase")]
pub enum Kind {
    Group,
    Run {
        text: String,
    },
    Fill {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        ch: Option<char>,
    },
    Picture(Picture),
    Plane(Plane),
    Role {
        role: String,
        #[serde(default)]
        props: Value,
    },
}

/// A drawing over a node's rectangle.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Picture {
    /// The drawing (see `paw.canvas.paint`), in pixels of a rectangle `px`
    /// big, which a frontend scales to the node's.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ops: Option<Value>,
    /// Or the content key of a drawing too big to send each time, which a
    /// frontend asks for once (`scene.blob`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub blob: Option<String>,
    pub px: [f32; 2],
    /// Under the cells drawn in its rectangle (their backgrounds under it,
    /// their text over it), as `buf:strip` with `under` keeps it; else over.
    #[serde(default)]
    pub under: bool,
}

/// How a plane's domain maps to units along one way: `per` units for each
/// unit of the domain (negative to run up or left), `from` at its edge.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Axis {
    pub domain: String,
    pub from: f64,
    pub per: f64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Plane {
    pub x: Axis,
    pub y: Axis,
}

/// What a press landed on: the node's key and hit, where, in the domain of
/// the innermost plane it is in (in units of the scene else), and the part
/// of the scene the hit region covers, in units (x, y, width, height).
#[derive(Clone, Debug, PartialEq)]
pub struct Hit {
    pub key: String,
    pub hit: Value,
    pub at: [f64; 2],
    pub rect: [f64; 4],
}

/// What [`Scene::placed`] calls for each node: the node, where it is and
/// what it is cut to (each as left, top, right, bottom).
pub type Visit<'a> = dyn FnMut(&Node, [f64; 4], [f64; 4]) + 'a;

/// A scene: the nodes of one window by key, in order from the root.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Scene {
    /// Its size in units.
    pub size: [f32; 2],
    pub root: Vec<String>,
    pub nodes: HashMap<String, Node>,
    /// The colours `default` stands for: the theme's text and background.
    pub fg: String,
    pub bg: String,
    /// Where the text cursor is, when the view shows one, in units.
    pub cursor: Option<[f32; 2]>,
    /// How many patches made it.
    pub rev: u64,
}

/// What changed of a window's scene: everything but `win` and `rev` is left
/// out when it did not.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Patch {
    pub win: String,
    pub rev: u64,
    /// The whole scene: what the frontend had of the window goes first.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub full: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size: Option<[f32; 2]>,
    /// The keys of the root's kids, in order.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub root: Option<Vec<String>>,
    /// Nodes new or changed (a node whose kids changed among them).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub set: Vec<Node>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub drop: Vec<String>,
    /// `[fg, bg]`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub colors: Option<[String; 2]>,
    /// `[x, y]`, or `[]` for none.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cursor: Option<Vec<f32>>,
}

impl Patch {
    /// Whether it changes nothing.
    pub fn is_empty(&self) -> bool {
        !self.full
            && self.size.is_none()
            && self.root.is_none()
            && self.set.is_empty()
            && self.drop.is_empty()
            && self.colors.is_none()
            && self.cursor.is_none()
    }
}

/// How a space maps to the scene's units, along x and along y:
/// `unit = a + b * value`. The root's space is the scene's units; a plane's
/// kids are in its domain; any other node's kids are placed from its corner.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Map {
    pub x: (f64, f64),
    pub y: (f64, f64),
}

impl Map {
    pub const UNITS: Map = Map { x: (0.0, 1.0), y: (0.0, 1.0) };

    /// A rectangle of this space in units, edges in order.
    pub fn rect(&self, r: &Units) -> [f64; 4] {
        let along = |(a, b): (f64, f64), at: f32, len: f32| {
            let (p, q) = (a + b * at as f64, a + b * (at + len) as f64);
            (p.min(q), p.max(q))
        };
        let (x0, x1) = along(self.x, r[0], r[2]);
        let (y0, y1) = along(self.y, r[1], r[3]);
        [x0, y0, x1, y1]
    }

    /// A rectangle in units (left, top, right, bottom) as this space has
    /// it: the other way from [`Map::rect`].
    pub fn unrect(&self, r: [f64; 4]) -> Units {
        let along = |(a, b): (f64, f64), p: f64, q: f64| {
            let (p, q) = ((p - a) / b, (q - a) / b);
            (p.min(q), (q - p).abs())
        };
        let (x, w) = along(self.x, r[0], r[2]);
        let (y, h) = along(self.y, r[1], r[3]);
        [x as f32, y as f32, w as f32, h as f32]
    }

    /// The space of a node's kids.
    pub fn inside(&self, node: &Node) -> Map {
        let (r, (ax, bx), (ay, by)) = (&node.rect, self.x, self.y);
        match &node.kind {
            Kind::Plane(plane) => Map {
                x: (ax + bx * (r[0] as f64 - plane.x.per * plane.x.from), bx * plane.x.per),
                y: (ay + by * (r[1] as f64 - plane.y.per * plane.y.from), by * plane.y.per),
            },
            _ => Map { x: (ax + bx * r[0] as f64, bx), y: (ay + by * r[1] as f64, by) },
        }
    }

    /// A point in units, in this space.
    pub fn back(&self, at: [f64; 2]) -> [f64; 2] {
        [(at[0] - self.x.0) / self.x.1, (at[1] - self.y.0) / self.y.1]
    }
}

fn overlap(a: [f64; 4], b: [f64; 4]) -> [f64; 4] {
    [a[0].max(b[0]), a[1].max(b[1]), a[2].min(b[2]), a[3].min(b[3])]
}

/// What a node's kids are cut to: a group or a plane cuts them to itself; a
/// role's are its cells, whole cells where a terminal snaps it, which may
/// stand a little past a rectangle that is not whole (a note in a plane):
/// each write of them keeps its own cut.
fn kids_cut(node: &Node, cut: [f64; 4], rect: [f64; 4]) -> [f64; 4] {
    if matches!(node.kind, Kind::Role { .. }) { cut } else { overlap(cut, rect) }
}

/// A rectangle in units as the whole cells it covers. An edge a hair
/// short of a cell's, as a cell placed in a plane comes back from its
/// domain, is that cell's.
fn whole(r: [f64; 4]) -> Rect {
    let cell = |v: f64| (v + 1e-3).floor() as i32;
    let (x, y) = (cell(r[0]), cell(r[1]));
    Rect { x, y, w: (cell(r[2]) - x).max(0), h: (cell(r[3]) - y).max(0) }
}

impl Scene {
    pub fn new(size: [f32; 2]) -> Scene {
        Scene { size, ..Scene::default() }
    }

    /// Add a node as the last kid of `parent` (of the root without).
    pub fn push(&mut self, parent: Option<&str>, node: Node) {
        let key = node.key.clone();
        match parent.and_then(|p| self.nodes.get_mut(p)) {
            Some(parent) => parent.kids.push(key.clone()),
            None => self.root.push(key.clone()),
        }
        self.nodes.insert(key, node);
    }

    /// What changed from `old` to `new`, for the window `win`.
    pub fn diff(old: &Scene, new: &Scene, win: &str) -> Patch {
        let mut patch = Patch { win: win.to_string(), rev: old.rev + 1, ..Patch::default() };
        if old.size != new.size {
            patch.size = Some(new.size);
        }
        if old.root != new.root {
            patch.root = Some(new.root.clone());
        }
        // In drawing order, so that a patch reads as the scene does.
        new.walk(&mut |node| {
            if old.nodes.get(&node.key) != Some(node) {
                patch.set.push(node.clone());
            }
        });
        let mut gone: Vec<String> = old.nodes.keys().filter(|k| !new.nodes.contains_key(*k)).cloned().collect();
        gone.sort();
        patch.drop = gone;
        if (&old.fg, &old.bg) != (&new.fg, &new.bg) {
            patch.colors = Some([new.fg.clone(), new.bg.clone()]);
        }
        if old.cursor != new.cursor {
            patch.cursor = Some(new.cursor.map_or_else(Vec::new, |c| c.to_vec()));
        }
        patch
    }

    /// Take in a patch made by [`Scene::diff`] against this scene (or
    /// against none, for a full one).
    pub fn apply(&mut self, patch: &Patch) {
        if patch.full {
            *self = Scene::default();
        }
        self.rev = patch.rev;
        if let Some(size) = patch.size {
            self.size = size;
        }
        if let Some(root) = &patch.root {
            self.root = root.clone();
        }
        for key in &patch.drop {
            self.nodes.remove(key);
        }
        for node in &patch.set {
            self.nodes.insert(node.key.clone(), node.clone());
        }
        if let Some([fg, bg]) = &patch.colors {
            (self.fg, self.bg) = (fg.clone(), bg.clone());
        }
        if let Some(cursor) = &patch.cursor {
            self.cursor = (cursor.len() == 2).then(|| [cursor[0], cursor[1]]);
        }
    }

    /// Every node reachable from the root, in drawing order.
    pub fn walk<'a>(&'a self, f: &mut dyn FnMut(&'a Node)) {
        let mut seen = HashSet::new();
        self.walk_from(&self.root, &mut seen, f);
    }

    fn walk_from<'a>(&'a self, keys: &'a [String], seen: &mut HashSet<&'a str>, f: &mut dyn FnMut(&'a Node)) {
        for key in keys {
            // A key named twice, or a node its own kid, is drawn once.
            if let Some(node) = self.nodes.get(key)
                && seen.insert(key.as_str())
            {
                f(node);
                self.walk_from(&node.kids, seen, f);
            }
        }
    }

    /// What is under a point in units: the last node drawn there that is a
    /// hit region, inside every group and plane it is in.
    pub fn hit(&self, at: [f32; 2]) -> Option<Hit> {
        let at = [at[0] as f64, at[1] as f64];
        let all = [0.0, 0.0, self.size[0] as f64, self.size[1] as f64];
        self.hit_in(&self.root, Map::UNITS, all, at, 0)
    }

    fn hit_in(&self, keys: &[String], map: Map, cut: [f64; 4], at: [f64; 2], depth: usize) -> Option<Hit> {
        if depth > 64 {
            return None;
        }
        let inside = |r: [f64; 4]| at[0] >= r[0] && at[0] < r[2] && at[1] >= r[1] && at[1] < r[3];
        for key in keys.iter().rev() {
            let Some(node) = self.nodes.get(key) else { continue };
            let mut cut = cut;
            if let Some(clip) = &node.clip {
                cut = overlap(cut, map.rect(clip));
            }
            let rect = overlap(map.rect(&node.rect), cut);
            if !inside(rect) {
                continue;
            }
            if !node.kids.is_empty()
                && let Some(found) = self.hit_in(&node.kids, map.inside(node), rect, at, depth + 1)
            {
                return Some(found);
            }
            if let Some(hit) = &node.hit {
                let space = if matches!(node.kind, Kind::Plane(_)) { map.inside(node) } else { map };
                let rect = [rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1]];
                return Some(Hit { key: node.key.clone(), hit: hit.clone(), at: space.back(at), rect });
            }
        }
        None
    }

    /// Every node reachable from the root, in drawing order, with where it
    /// is in units of the scene and what it is cut to there (each as left,
    /// top, right, bottom): what a frontend paints a role by.
    pub fn placed(&self, f: &mut Visit<'_>) {
        let all = [0.0, 0.0, self.size[0] as f64, self.size[1] as f64];
        self.placed_in(&self.root, Map::UNITS, all, f, 0);
    }

    fn placed_in(&self, keys: &[String], map: Map, cut: [f64; 4], f: &mut Visit<'_>, depth: usize) {
        if depth > 64 {
            return;
        }
        for key in keys {
            let Some(node) = self.nodes.get(key) else { continue };
            let mut cut = cut;
            if let Some(clip) = &node.clip {
                cut = overlap(cut, map.rect(clip));
            }
            let rect = map.rect(&node.rect);
            f(node, rect, cut);
            self.placed_in(&node.kids, map.inside(node), kids_cut(node, cut, rect), f, depth + 1);
        }
    }

    /// The runs and fills drawn after a role that a frontend paints itself
    /// (`known`) and over it, with where they are and what they are cut to
    /// in units (left, top, right, bottom). A frontend that paints its roles
    /// over the cells paints these over the roles again, so that what a
    /// view drew over a role (a tag on a note, the selection, the cursor)
    /// shows there as a terminal shows it.
    pub fn over_roles(&self, known: &dyn Fn(&str) -> bool) -> Vec<(Node, [f64; 4], [f64; 4])> {
        let mut roles: Vec<[f64; 4]> = Vec::new();
        let mut out = Vec::new();
        let crosses = |a: &[f64; 4], b: &[f64; 4]| a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3];
        self.placed(&mut |node, rect, cut| match &node.kind {
            Kind::Role { role, .. } if known(role) => roles.push(overlap(rect, cut)),
            Kind::Run { .. } | Kind::Fill { .. } if !roles.is_empty() => {
                let shown = overlap(rect, cut);
                if roles.iter().any(|r| crosses(r, &shown)) {
                    out.push((node.clone(), rect, cut));
                }
            }
            _ => {}
        });
        out
    }

    /// Lower the scene for a frontend that draws the roles `known` itself:
    /// such a role's kids (its cells, for a frontend that does not) are
    /// left out.
    pub fn lower(&mut self, known: &dyn Fn(&str) -> bool) {
        let mut gone = Vec::new();
        for node in self.nodes.values_mut() {
            if let Kind::Role { role, .. } = &node.kind
                && known(role)
            {
                gone.append(&mut node.kids);
            }
        }
        while let Some(key) = gone.pop() {
            if let Some(mut node) = self.nodes.remove(&key) {
                gone.append(&mut node.kids);
            }
        }
    }

    /// The scene as a terminal shows it: its runs and fills written in
    /// order, groups and planes placing and cutting their kids, a role it
    /// draws as its kids. Pictures have no cells.
    pub fn to_cells(&self) -> Cells {
        let (w, h) = (self.size[0].max(0.0) as u16, self.size[1].max(0.0) as u16);
        let mut cells = Cells::new(w, h);
        let all = [0.0, 0.0, w as f64, h as f64];
        self.cells_in(&self.root, Map::UNITS, all, &mut cells, 0);
        cells
    }

    fn cells_in(&self, keys: &[String], map: Map, cut: [f64; 4], cells: &mut Cells, depth: usize) {
        if depth > 64 {
            return;
        }
        for key in keys {
            let Some(node) = self.nodes.get(key) else { continue };
            let mut cut = cut;
            if let Some(clip) = &node.clip {
                cut = overlap(cut, map.rect(clip));
            }
            let rect = map.rect(&node.rect);
            match &node.kind {
                Kind::Run { text } => {
                    let at = whole(rect);
                    cells.text(whole(cut), at.x, at.y, text, node.style);
                }
                Kind::Fill { ch } => cells.fill(whole(cut), whole(rect), *ch, node.style),
                Kind::Picture(_) => {}
                Kind::Group | Kind::Plane(_) | Kind::Role { .. } => {
                    self.cells_in(&node.kids, map.inside(node), kids_cut(node, cut, rect), cells, depth + 1)
                }
            }
        }
    }

    /// The scene's colours for `default`, as red, green and blue.
    pub fn colors(&self) -> ((u8, u8, u8), (u8, u8, u8)) {
        let parse = |text: &str, or: (u8, u8, u8)| match Color::parse(text) {
            Some(color) => cells::rgb(color, or),
            None => or,
        };
        (parse(&self.fg, (0xd8, 0xd9, 0xdc)), parse(&self.bg, (0x18, 0x19, 0x1c)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use cells::BOLD;
    use serde_json::json;

    fn run(key: &str, x: f32, y: f32, text: &str) -> Node {
        Node::new(key, Kind::Run { text: text.into() }, [x, y, text.chars().count() as f32, 1.0])
    }

    fn fill(key: &str, rect: Units, ch: Option<char>, style: Style) -> Node {
        Node { style, ..Node::new(key, Kind::Fill { ch }, rect) }
    }

    fn lines(cells: &Cells) -> Vec<String> {
        cells.cells.chunks(cells.width as usize).map(|row| row.iter().map(|c| c.ch).collect()).collect()
    }

    /// A roll: a plane of beats along x (two units a beat, from beat 4)
    /// and pitches running up (one row each, pitch 64 at the top).
    fn roll() -> Scene {
        let mut scene = Scene::new([20.0, 6.0]);
        scene.push(None, fill("bg", [0.0, 0.0, 20.0, 6.0], Some('.'), Style::default()));
        let plane = Plane {
            x: Axis { domain: "beat".into(), from: 4.0, per: 2.0 },
            y: Axis { domain: "pitch".into(), from: 65.0, per: -1.0 },
        };
        let mut grid = Node::new("roll", Kind::Plane(plane), [2.0, 1.0, 16.0, 4.0]);
        grid.hit = Some(json!({ "kind": "grid" }));
        scene.push(None, grid);
        let mut note = Node::new("note:1", Kind::Role { role: "note".into(), props: json!({ "velocity": 100 }) }, [5.0, 62.0, 1.5, 1.0]);
        note.hit = Some(json!({ "kind": "note", "id": 1 }));
        scene.push(Some("roll"), note);
        // The note's cells, which a frontend that does not know notes draws.
        scene.push(Some("note:1"), fill("note:1/cells", [0.0, 0.0, 1.5, 1.0], Some('█'), Style::default()));
        scene
    }

    #[test]
    fn a_patch_carries_what_changed_and_makes_the_same_scene() {
        let mut old = Scene::new([10.0, 2.0]);
        old.push(None, run("a", 0.0, 0.0, "one"));
        old.push(None, run("b", 0.0, 1.0, "two"));
        old.push(None, run("c", 5.0, 1.0, "gone"));
        let mut new = old.clone();
        new.nodes.get_mut("b").unwrap().kind = Kind::Run { text: "TWO".into() };
        new.nodes.remove("c");
        new.root.retain(|k| k != "c");
        new.push(None, fill("d", [0.0, 0.0, 10.0, 1.0], None, Style { on: BOLD, ..Style::default() }));
        new.cursor = Some([1.0, 1.0]);
        let patch = Scene::diff(&old, &new, "3");
        assert_eq!(patch.set.iter().map(|n| n.key.as_str()).collect::<Vec<_>>(), vec!["b", "d"]);
        assert_eq!(patch.drop, vec!["c".to_string()]);
        assert_eq!(patch.root.as_deref(), Some(&["a".to_string(), "b".into(), "d".into()][..]));
        assert_eq!(patch.size, None, "the size did not change");
        // Over the wire and back, then applied: the scene the kernel has.
        let wire = serde_json::to_string(&patch).unwrap();
        let mut copy = old.clone();
        copy.apply(&serde_json::from_str(&wire).unwrap());
        assert_eq!((copy.root.clone(), copy.nodes.clone(), copy.cursor), (new.root.clone(), new.nodes.clone(), new.cursor));
        assert!(Scene::diff(&new, &new, "3").is_empty(), "nothing changed, nothing to say");
    }

    #[test]
    fn each_kind_of_node_comes_back_the_same_from_the_wire() {
        // The golden file of `each_kind` holds what goes on the wire.
        for node in each_kind().nodes.values() {
            let back: Node = serde_json::from_value(serde_json::to_value(node).unwrap()).unwrap();
            assert_eq!(&back, node, "node {}", node.key);
        }
    }

    #[test]
    fn a_patch_with_nothing_but_a_moved_cursor_is_small() {
        let mut old = Scene::new([80.0, 24.0]);
        for y in 0..24 {
            old.push(None, run(&format!("t0,{y}"), 0.0, y as f32, &"x".repeat(80)));
        }
        let mut new = old.clone();
        new.cursor = Some([4.0, 4.0]);
        let wire = serde_json::to_string(&Scene::diff(&old, &new, "1")).unwrap();
        assert_eq!(wire, r#"{"win":"1","rev":1,"cursor":[4.0,4.0]}"#);
    }

    #[test]
    fn a_scene_lowers_to_the_cells_its_writes_make() {
        let mut scene = Scene::new([8.0, 2.0]);
        let back = Style { bg: Some(Color::Indexed(4)), ..Style::default() };
        scene.push(None, fill("bg", [0.0, 0.0, 8.0, 2.0], Some(' '), back));
        scene.push(None, run("a", 1.0, 0.0, "hello world"));
        // Cut to the first four columns, as a sub-buffer's writes are.
        let mut cut = run("b", 0.0, 1.0, "abcdefgh");
        cut.clip = Some([0.0, 1.0, 4.0, 1.0]);
        scene.push(None, cut);
        scene.push(None, fill("hl", [1.0, 0.0, 3.0, 1.0], None, Style { on: BOLD, ..Style::default() }));
        let cells = scene.to_cells();
        assert_eq!(lines(&cells), vec![" hello w", "abcd    "]);
        assert_eq!((cells.cells[0].attrs, cells.cells[1].attrs, cells.cells[4].attrs), (0, BOLD, 0));
        assert_eq!(cells.cells[9].bg, Color::Indexed(4), "text keeps the background under it");
    }

    #[test]
    fn a_plane_places_its_kids_by_their_domain_and_a_role_draws_its_cells() {
        let cells = roll().to_cells();
        // Beat 5 is two units into the plane (x 2 + 2); pitch 62 is the
        // third row of the plane (y 1 + 2), whose top edge is pitch 65 and
        // whose first row is pitch 64. A beat and a half is three units.
        assert_eq!(lines(&cells)[3], "....███.............");
        assert!(lines(&cells).iter().enumerate().all(|(y, l)| y == 3 || !l.contains('█')));
    }

    #[test]
    fn a_hit_finds_the_last_region_drawn_and_says_where_in_its_plane() {
        let scene = roll();
        let on_note = scene.hit([4.5, 3.5]).unwrap();
        assert_eq!((on_note.key.as_str(), on_note.hit["id"].as_i64()), ("note:1", Some(1)));
        // In the plane's domain: 2.5 units into it is beat 4 + 2.5 / 2,
        // 2.5 rows down is pitch 65 - 2.5.
        assert_eq!(on_note.at, [5.25, 62.5]);
        assert_eq!(on_note.rect, [4.0, 3.0, 3.0, 1.0], "the note's place in units");
        let empty = scene.hit([10.0, 1.5]).unwrap();
        assert_eq!((empty.key.as_str(), empty.at), ("roll", [8.0, 64.5]));
        assert_eq!(scene.hit([0.5, 0.5]), None, "the background is no hit region");
        assert_eq!(scene.hit([19.0, 5.5]), None, "nor is anything outside the plane");
    }

    #[test]
    fn a_role_known_to_a_frontend_goes_without_its_cells_and_is_placed() {
        let mut scene = roll();
        let mut lowered = scene.clone();
        lowered.lower(&|role| role == "note");
        assert!(lowered.nodes["note:1"].kids.is_empty() && !lowered.nodes.contains_key("note:1/cells"));
        assert!(!lowered.to_cells().cells.iter().any(|c| c.ch == '█'), "no cells for it: the frontend paints it");
        scene.lower(&|role| role == "clip");
        assert_eq!(scene, roll(), "a role it does not know keeps its cells");
        let mut seen = Vec::new();
        lowered.placed(&mut |node, rect, _| seen.push((node.key.clone(), rect)));
        assert_eq!(seen.last(), Some(&("note:1".to_string(), [4.0, 3.0, 7.0, 4.0])), "where the note is in units");
    }

    #[test]
    fn a_plane_may_run_time_down_and_its_hits_say_where_in_time() {
        // A tracker: lanes across, three units each; beats down, four rows
        // a beat from beat 2.
        let mut scene = Scene::new([12.0, 8.0]);
        let plane = Plane {
            x: Axis { domain: "lane".into(), from: 0.0, per: 3.0 },
            y: Axis { domain: "beat".into(), from: 2.0, per: 4.0 },
        };
        let mut grid = Node::new("pattern", Kind::Plane(plane), [0.0, 0.0, 12.0, 8.0]);
        grid.hit = Some(json!({ "kind": "cell" }));
        scene.push(None, grid);
        // A note in lane 1 at beat 2.75, a quarter beat long: one row.
        let mut note = Node::new("n", Kind::Role { role: "note".into(), props: json!({}) }, [1.0, 2.75, 1.0, 0.25]);
        note.hit = Some(json!({ "kind": "note" }));
        scene.push(Some("pattern"), note);
        scene.push(Some("n"), fill("n/cells", [0.0, 0.0, 1.0, 0.25], Some('C'), Style::default()));
        let rows = lines(&scene.to_cells());
        assert_eq!(rows[3], "   CCC      ", "lane 1, the fourth row");
        let on = scene.hit([4.5, 3.5]).unwrap();
        assert_eq!((on.key.as_str(), on.at), ("n", [1.5, 2.875]));
        let off = scene.hit([10.5, 6.0]).unwrap();
        assert_eq!(off.at, [3.5, 3.5], "lane 3, beat three and a half");
    }

    #[test]
    fn what_is_drawn_over_a_painted_role_is_found_to_paint_over_it_again() {
        let mut scene = roll();
        scene.lower(&|role| role == "note");
        // Before the note, under it: not over it. After it: a tag on the
        // note, and a line elsewhere.
        scene.root.insert(1, "under".into());
        scene.nodes.insert("under".into(), run("under", 4.0, 3.0, "x"));
        scene.push(None, run("tag", 5.0, 3.0, "[]"));
        scene.push(None, run("far", 12.0, 5.0, "y"));
        let over = scene.over_roles(&|role| role == "note");
        assert_eq!(over.iter().map(|(n, ..)| n.key.as_str()).collect::<Vec<_>>(), vec!["tag"]);
        assert_eq!(over[0].1, [5.0, 3.0, 7.0, 4.0], "where it is in units");
        assert!(scene.over_roles(&|_| false).is_empty(), "nothing is over a role painted in cells");
    }

    #[test]
    fn a_roles_cells_snapped_past_its_rectangle_still_show() {
        // A note from 2.4 to 4.6 units, which a terminal rounds to columns
        // 2 to 4: its last cell lies past its rectangle.
        let mut scene = Scene::new([8.0, 1.0]);
        scene.push(None, Node::new("n", Kind::Role { role: "note".into(), props: json!({}) }, [2.4, 0.0, 2.2, 1.0]));
        scene.push(Some("n"), fill("n/cells", [-0.4, 0.0, 3.0, 1.0], Some('#'), Style::default()));
        assert_eq!(lines(&scene.to_cells())[0], "  ###   ");
    }

    /// A window with one node of each kind, and each field a node may
    /// have: a part row (a group with a cut, its name, a highlight, a
    /// fader role and its cells), a roll (a plane with a note role), and two pictures,
    /// one drawn inline and one sent by its content key.
    fn each_kind() -> Scene {
        let mut scene = Scene::new([24.0, 6.0]);
        scene.fg = "#d0d0d0".into();
        scene.bg = "#101010".into();
        scene.cursor = Some([3.0, 1.0]);
        scene.push(None, fill("bg", [0.0, 0.0, 24.0, 6.0], Some(' '), Style { bg: Some(Color::Indexed(235)), ..Style::default() }));
        let mut row = Node::new("part:1", Kind::Group, [0.0, 0.0, 24.0, 1.0]);
        row.clip = Some([0.0, 0.0, 12.5, 1.0]);
        row.hit = Some(json!({ "kind": "part", "id": 1 }));
        scene.push(None, row);
        let mut name = run("part:1/name", 0.0, 0.0, "Bass");
        name.style = Style { fg: Some(Color::Rgb(255, 128, 0)), on: BOLD, ..Style::default() };
        scene.push(Some("part:1"), name);
        // A highlight: a fill that keeps the characters under it.
        scene.push(Some("part:1"), fill("part:1/selected", [0.0, 0.0, 4.0, 1.0], None, Style { off: BOLD, ..Style::default() }));
        let mut fader = Node::new("fader:1", Kind::Role { role: "fader".into(), props: json!({ "db": -6.0, "min": -60.0 }) }, [6.0, 0.0, 6.0, 1.0]);
        fader.bind = Some("meter:1".into());
        scene.push(Some("part:1"), fader);
        scene.push(Some("fader:1"), fill("fader:1/cells", [0.0, 0.0, 4.5, 1.0], Some('='), Style::default()));
        for node in roll().nodes.into_values().filter(|n| n.key != "bg") {
            scene.nodes.insert(node.key.clone(), node);
        }
        scene.root.push("roll".into());
        let ops = json!([{ "op": "line", "from": [0, 0], "to": [16, 8], "color": "#ffffff" }]);
        scene.push(None, Node::new("scope", Kind::Picture(Picture { ops: Some(ops), blob: None, px: [16.0, 8.0], under: false }), [20.0, 1.0, 4.0, 2.0]));
        scene.push(None, Node::new("wave", Kind::Picture(Picture { ops: None, blob: Some("pic:1f".into()), px: [64.0, 16.0], under: true }), [20.0, 3.0, 4.0, 2.0]));
        scene
    }

    /// A patch as text: its fields but the nodes on the first line, then
    /// each node as it goes on the wire, one to a line.
    fn wire_lines(patch: &Patch) -> String {
        let head = Patch { set: Vec::new(), ..patch.clone() };
        let mut text = serde_json::to_string(&head).unwrap();
        for node in &patch.set {
            text.push('\n');
            text.push_str(&serde_json::to_string(node).unwrap());
        }
        text
    }

    #[test]
    fn a_new_window_sends_each_kind_of_node_as_the_golden_file_has_it() {
        let mut patch = Scene::diff(&Scene::default(), &each_kind(), "1");
        // As the kernel sends the first scene of a window.
        patch.full = true;
        insta::assert_snapshot!(wire_lines(&patch));
    }

    #[test]
    fn a_kid_outside_its_group_neither_shows_nor_is_hit() {
        let mut scene = Scene::new([10.0, 3.0]);
        scene.push(None, Node::new("g", Kind::Group, [2.0, 1.0, 3.0, 1.0]));
        let mut wide = run("g/t", 0.0, 0.0, "abcdef");
        wide.hit = Some(json!("text"));
        scene.push(Some("g"), wide);
        assert_eq!(lines(&scene.to_cells())[1], "  abc     ");
        assert!(scene.hit([4.5, 1.5]).is_some());
        assert_eq!(scene.hit([6.5, 1.5]), None, "cut to the group");
    }
}
