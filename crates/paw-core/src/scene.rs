//! Scenes in the kernel (see crates/paw-scene): a view drawn for a graphical
//! frontend is kept as the nodes its writes make, and the frontend is sent
//! what changed of it since the last time, as a patch.
//!
//! While a view is drawn for a scene (`scene_draw`), every `grid_text` and
//! `grid_fill` is kept as a run or a fill node besides being written to the
//! grid, so that the scene lowered to cells is what the view drew. Nodes are
//! named by what they are and where (`t3,5` the text written at column 3 of
//! row 5), so that a view drawn again names what stayed the same alike and
//! a patch carries only what moved. Drawings too big to send each time are
//! sent by a content key, which the frontend asks for once (`scene_blob`).
//!
//! What is sent when, and to whom, is runtime/lua/paw/scene.tl's to say.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_possible_wrap, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

use std::collections::{HashMap, HashSet};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::rc::Rc;

use mlua::serde::DeserializeOptions;
use mlua::{Lua, LuaSerdeExt, Table, Value as LuaValue};
use paw_scene::cells::{Rect, Style};
use paw_scene::color::Rgba;
use paw_scene::{Axis, Kind, Map, Node, Picture, Plane, Scene};
use serde::Deserialize;
use serde_json::Value;
use unicode_width::UnicodeWidthStr;

use crate::api::{Shared, from_lua, guarded, to_lua};

/// A drawing whose operations take more than this as JSON is sent by its
/// content key.
const BLOB_SIZE: usize = 16 << 10;

/// A node open (`scene_open`): what is written goes into it, placed in
/// its kids' space (`map`, from that space to the scene's units).
struct Open {
    key: String,
    map: Map,
    /// A plane opened to put a node in it (`into`), closed with that node.
    with: bool,
}

/// A plane of the scene (`scene_open` with `plane`), which nodes are put
/// into later by its key (`into`): the node it is in, its own node as it
/// was made, the node that has its kids now, and its kids' space. A plane
/// put into after something else was drawn after it goes on in a node of
/// its own past that, so that the scene draws in the order the view did.
struct PlaneAt {
    parent: Option<String>,
    node: Node,
    current: String,
    map: Map,
    parts: u32,
}

/// A scene being made, and how many nodes of each name it has.
struct Building {
    scene: Scene,
    names: HashMap<String, u32>,
    /// Writes to the grid are being kept.
    recording: bool,
    /// The nodes open (a role being drawn), innermost last.
    open: Vec<Open>,
    /// The planes made, by the key they were given.
    planes: HashMap<String, PlaneAt>,
}

#[derive(Default)]
pub(crate) struct Scenes {
    building: Option<Building>,
    /// What each connection was last sent of each window's scene.
    kept: HashMap<(u64, String), Scene>,
    /// Drawings sent by content key, for each connection.
    blobs: HashMap<u64, HashMap<String, Value>>,
    /// The roles each connection draws itself: their cells are not sent.
    roles: HashMap<u64, HashSet<String>>,
}

impl Building {
    fn new(scene: Scene, recording: bool) -> Building {
        Building { scene, names: HashMap::new(), recording, open: Vec::new(), planes: HashMap::new() }
    }

    /// A name of its own for a node: `base`, then `base#2`..., under the
    /// name of the node it is in.
    fn name(&mut self, base: String) -> String {
        let base = match self.open.last() {
            Some(open) => format!("{}/{base}", open.key),
            None => base,
        };
        let count = self.names.entry(base.clone()).or_insert(0);
        *count += 1;
        if *count == 1 { base } else { format!("{base}#{count}") }
    }

    /// The space writes go into: the open node's kids', or the scene's units.
    fn map(&self) -> Map {
        self.open.last().map_or(Map::UNITS, |open| open.map)
    }

    /// The cell the space writes go into starts in, which their names
    /// count from.
    fn origin(&self) -> [i32; 2] {
        let map = self.map();
        [map.x.0.floor() as i32, map.y.0.floor() as i32]
    }

    /// A rectangle of the scene's units in the space writes go into.
    fn local(&self, r: [f32; 4]) -> [f32; 4] {
        let [x, y, w, h] = r.map(f64::from);
        self.map().unrect([x, y, x + w, y + h])
    }

    /// The part of the scene a write is cut to: nothing when it is all of it.
    fn cut(&self, clip: Rect) -> Option<[f32; 4]> {
        let size = self.scene.size;
        let all = Rect { x: 0, y: 0, w: size[0] as i32, h: size[1] as i32 };
        let clip = clip.intersect(&all);
        (clip != all || !self.open.is_empty()).then(|| self.local(units(clip)))
    }

    /// Put a node in, its rectangle in the space of the node open (or the
    /// root's), as that node's last kid.
    fn push(&mut self, node: Node) {
        let parent = self.open.last().map(|open| open.key.clone());
        self.scene.push(parent.as_deref(), node);
    }

    /// Open the plane made as `key` to put a node in it: in a node of its
    /// own after whatever was drawn since its last. False for a plane that
    /// was not made.
    fn into(&mut self, key: &str) -> bool {
        let Some(plane) = self.planes.get_mut(key) else { return false };
        let kids = match &plane.parent {
            Some(parent) => self.scene.nodes.get(parent).map(|n| &n.kids),
            None => Some(&self.scene.root),
        };
        if kids.and_then(|k| k.last()) != Some(&plane.current) {
            plane.parts += 1;
            let mut node = plane.node.clone();
            node.key = format!("{}#{}", plane.node.key, plane.parts);
            // The plane's own hit region is its first node's: one over it
            // again would hide what is in that one from the pointer.
            node.hit = None;
            plane.current = node.key.clone();
            self.scene.push(plane.parent.as_deref(), node);
        }
        self.open.push(Open { key: plane.current.clone(), map: plane.map, with: true });
        true
    }

    fn visible(&self, clip: Rect, area: Rect) -> bool {
        let size = self.scene.size;
        let all = Rect { x: 0, y: 0, w: size[0] as i32, h: size[1] as i32 };
        let shown = area.intersect(&clip).intersect(&all);
        shown.w > 0 && shown.h > 0
    }
}

impl Scenes {
    /// Text written to the grid: a run, while a view is drawn for a scene.
    pub(crate) fn text(&mut self, clip: Rect, x: i32, y: i32, text: &str, style: Style) {
        let Some(b) = self.building.as_mut().filter(|b| b.recording) else { return };
        let cols = text.width() as i32;
        let area = Rect { x, y, w: cols, h: 1 };
        if !b.visible(clip, area) {
            return;
        }
        let [ox, oy] = b.origin();
        let key = b.name(format!("t{},{}", x - ox, y - oy));
        let mut node = Node::new(key, Kind::Run { text: text.to_string() }, b.local(units(area)));
        node.clip = b.cut(clip);
        node.style = style;
        b.push(node);
    }

    /// An area restyled or filled: a fill, while a view is drawn for a scene.
    pub(crate) fn fill(&mut self, clip: Rect, area: Rect, ch: Option<char>, style: Style) {
        let Some(b) = self.building.as_mut().filter(|b| b.recording) else { return };
        if !b.visible(clip, area) {
            return;
        }
        let [ox, oy] = b.origin();
        let key = b.name(format!("f{},{},{},{}", area.x - ox, area.y - oy, area.w, area.h));
        let mut node = Node::new(key, Kind::Fill { ch }, b.local(units(area)));
        node.clip = b.cut(clip);
        node.style = style;
        b.push(node);
    }

    /// Open a node over `rect` (see `scene_open`): true when one was, to be
    /// closed.
    fn open(&mut self, rect: [f32; 4], opts: OpenOpts) -> Result<bool, String> {
        let Some(b) = self.building.as_mut().filter(|b| b.recording) else { return Ok(false) };
        if let Some(plane) = &opts.into
            && !b.into(plane)
        {
            return Ok(false);
        }
        // In a plane's domain as given; else from the scene's units.
        let local = if opts.into.is_some() { rect } else { b.local(rect) };
        let [ox, oy] = b.origin();
        let what = opts.role.as_deref().unwrap_or(if opts.plane.is_some() { "plane" } else { "g" });
        let base = opts.key.clone().unwrap_or_else(|| format!("{what}@{},{}", rect[0] - ox as f32, rect[1] - oy as f32));
        let key = b.name(base);
        let kind = match (opts.role, opts.plane) {
            (Some(role), _) => Kind::Role { role, props: opts.props.unwrap_or(Value::Null) },
            (None, Some(plane)) => Kind::Plane(Plane { x: plane.x, y: plane.y }),
            (None, None) => Kind::Group,
        };
        let mut node = Node::new(key.clone(), kind, local);
        node.clip = opts.clip.map(|c| b.local(c.units()));
        node.hit = opts.hit;
        node.bind = opts.bind;
        let map = b.map().inside(&node);
        if matches!(node.kind, Kind::Plane(_)) {
            let name = opts.key.unwrap_or_else(|| key.clone());
            if b.planes.contains_key(&name) {
                return Err(format!("two planes made as `{name}`"));
            }
            let parent = b.open.last().map(|open| open.key.clone());
            b.planes.insert(name, PlaneAt { parent, node: node.clone(), current: key.clone(), map, parts: 1 });
        }
        b.push(node);
        b.open.push(Open { key, map, with: false });
        Ok(true)
    }

    /// Close the node opened last, and the plane it was put into.
    fn close(&mut self) {
        let Some(b) = self.building.as_mut() else { return };
        b.open.pop();
        while b.open.last().is_some_and(|open| open.with) {
            b.open.pop();
        }
    }

    /// The scene made since `begin`, compared with what `client` was last
    /// sent of the window `id`: the patch to send it, or nothing when
    /// nothing changed. The new scene is kept in its place, lowered to
    /// what the connection draws (`roles`).
    fn end(&mut self, client: u64, id: &str) -> Option<String> {
        let mut scene = self.building.take()?.scene;
        if let Some(known) = self.roles.get(&client) {
            scene.lower(&|role| known.contains(role));
        }
        let blobs = self.blobs.entry(client).or_default();
        for node in scene.nodes.values_mut() {
            if let Kind::Picture(picture) = &mut node.kind
                && let Some(ops) = picture.ops.take()
            {
                // The pictures of pixels it shows are in use: kept before
                // those that are not.
                for key in paw_raster::pixels::keys_in(&ops) {
                    paw_raster::pixels::get(key);
                }
                let text = ops.to_string();
                if text.len() <= BLOB_SIZE {
                    picture.ops = Some(ops);
                    continue;
                }
                let mut hasher = DefaultHasher::new();
                text.hash(&mut hasher);
                let key = format!("pic:{:016x}", hasher.finish());
                blobs.insert(key.clone(), ops);
                picture.blob = Some(key);
            }
        }
        let key = (client, id.to_string());
        let old = self.kept.remove(&key);
        let mut patch = Scene::diff(old.as_ref().unwrap_or(&Scene::default()), &scene, id);
        patch.full = old.is_none();
        scene.rev = patch.rev;
        self.kept.insert(key, scene);
        self.prune(client);
        (!patch.is_empty()).then(|| serde_json::to_string(&patch).unwrap_or_default())
    }

    /// Forget what `client` was sent of the window `id`, or of every window
    /// and which roles it draws.
    fn forget(&mut self, client: u64, id: Option<&str>) {
        self.kept.retain(|(c, w), _| *c != client || id.is_some_and(|id| id != w));
        if id.is_none() {
            self.roles.remove(&client);
        }
        self.prune(client);
    }

    /// Keep only the drawings a kept scene of `client` names.
    fn prune(&mut self, client: u64) {
        let Some(blobs) = self.blobs.get_mut(&client) else { return };
        let mut named = std::collections::HashSet::new();
        for ((c, _), scene) in &self.kept {
            if *c == client {
                for node in scene.nodes.values() {
                    if let Kind::Picture(Picture { blob: Some(key), .. }) = &node.kind {
                        named.insert(key.clone());
                    }
                }
            }
        }
        blobs.retain(|key, _| named.contains(key));
        if blobs.is_empty() {
            self.blobs.remove(&client);
        }
    }
}

/// A rectangle of whole cells in units.
fn units(r: Rect) -> [f32; 4] {
    [r.x as f32, r.y as f32, r.w as f32, r.h as f32]
}

/// A rectangle as Lua gives it, `{ x, y, w, h }`.
#[derive(Deserialize)]
struct Area {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
}

impl Area {
    fn units(&self) -> [f32; 4] {
        [self.x, self.y, self.w, self.h]
    }
}

#[derive(Deserialize)]
struct PictureOpts {
    ops: Value,
    /// The size in pixels it was drawn at.
    px: [f32; 2],
    #[serde(default)]
    under: bool,
    /// The part of it that shows, when not all of it does.
    clip: Option<Area>,
}

#[derive(Deserialize)]
struct PlaneOpts {
    x: Axis,
    y: Axis,
}

#[derive(Deserialize)]
struct OpenOpts {
    role: Option<String>,
    props: Option<Value>,
    hit: Option<Value>,
    bind: Option<String>,
    key: Option<String>,
    clip: Option<Area>,
    plane: Option<PlaneOpts>,
    into: Option<String>,
}

#[expect(clippy::too_many_lines, reason = "one registration for each Lua function of the table, in a list")]
pub(crate) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    let sh = shared.clone();
    // Start a scene `w` by `h` units big, for `scene_draw` and
    // `scene_picture` to put nodes in.
    // @return nil
    api.set(
        "scene_begin",
        lua.create_function(guarded!("scene_begin", move |_, (w, h): (f32, f32)| {
            let scene = Scene::new([w.max(0.0), h.max(0.0)]);
            sh.scenes.borrow_mut().building = Some(Building::new(scene, false));
            Ok(())
        }))?,
    )?;
    let sh = shared.clone();
    // While a view is drawn for a scene: a node over a rectangle of it, in
    // units of the scene, that what is written until `scene_close` goes
    // into. `opts`: `role` (a group without), `props`, `hit` (a press on
    // it is on that), `bind` (`meter:4`), `key` (its name; the role and
    // where it is without), `clip` (the part that shows). With `plane`
    // (`{ x = axis, y = axis }`, each `{ domain, from, per }`, see
    // `paw_scene::Axis`) it is a plane, whose kids are placed in its domain;
    // with `into` (the key a plane was made with) it goes into that plane,
    // `rect` in the plane's domain. False when paw draws no scene now, or
    // there is no such plane, with nothing to close.
    // @param rect types.Rect
    // @param opts? types.SceneOpenOptions
    // @return boolean
    api.set(
        "scene_open",
        lua.create_function(guarded!("scene_open", move |lua, (rect, opts): (LuaValue, LuaValue)| {
            let rect: Area = from_lua(lua, rect)?;
            // A role's props are data for a frontend, where an empty Lua
            // table is most often an empty list (no warp markers): sent as
            // a map, it would not read as one, and the frontend would take
            // none of the props.
            let opts: OpenOpts = lua.from_value_with(opts, DeserializeOptions::new().encode_empty_tables_as_array(true))?;
            sh.scenes.borrow_mut().open(rect.units(), opts).map_err(mlua::Error::runtime)
        }))?,
    )?;
    let sh = shared.clone();
    // @return nil
    api.set(
        "scene_close",
        lua.create_function(guarded!("scene_close", move |_, ()| {
            sh.scenes.borrow_mut().close();
            Ok(())
        }))?,
    )?;
    let sh = shared.clone();
    // The roles `client` draws itself: in what it is sent from now on,
    // such a role goes without the cells that draw it for a terminal.
    // @return nil
    api.set(
        "scene_roles",
        lua.create_function(guarded!("scene_roles", move |_, (client, roles): (u64, Vec<String>)| {
            sh.scenes.borrow_mut().roles.insert(client, roles.into_iter().collect());
            Ok(())
        }))?,
    )?;
    let sh = shared.clone();
    // What is under the point `x, y` (units) of what `client` has of the
    // window `id`: `{ key, hit, at = { x, y }, rect = { x, y, w, h } }`
    // (see `paw_scene::Scene::hit`), or nil.
    // @return types.SceneHit
    api.set(
        "scene_hit",
        lua.create_function(guarded!("scene_hit", move |lua, (client, id, x, y): (u64, String, f32, f32)| {
            let scenes = sh.scenes.borrow();
            let Some(found) = scenes.kept.get(&(client, id)).and_then(|s| s.hit([x, y])) else { return Ok(LuaValue::Nil) };
            let [rx, ry, rw, rh] = found.rect;
            let out = serde_json::json!({
                "key": found.key, "hit": found.hit, "at": { "x": found.at[0], "y": found.at[1] },
                "rect": { "x": rx, "y": ry, "w": rw, "h": rh },
            });
            to_lua(lua, &out)
        }))?,
    )?;
    let sh = shared.clone();
    // Draw a view by itself, `cols` by `rows` cells, as a window shows it:
    // its writes are the scene's runs and fills, its cursor and its theme's
    // colors the scene's.
    // @return nil
    api.set(
        "scene_draw",
        lua.create_function(guarded!("scene_draw", move |lua, (name, cols, rows): (String, u16, u16)| {
            let start = |on: bool| -> mlua::Result<()> {
                match sh.scenes.borrow_mut().building.as_mut() {
                    Some(b) => {
                        b.recording = on;
                        Ok(())
                    }
                    None => Err(mlua::Error::runtime("scene_draw without scene_begin")),
                }
            };
            start(true)?;
            let drawn = crate::api::draw_view(lua, &sh, &name, cols.max(1), rows.max(1));
            start(false)?;
            let (_, cursor, fg, bg) = drawn?;
            let mut scenes = sh.scenes.borrow_mut();
            if let Some(b) = scenes.building.as_mut() {
                b.scene.cursor = cursor.map(|(x, y)| [x as f32, y as f32]);
                (b.scene.fg, b.scene.bg) = (Rgba::from(fg).to_string(), Rgba::from(bg).to_string());
            }
            Ok(())
        }))?,
    )?;
    let sh = shared.clone();
    // A drawing (`paw.canvas` operations) over a rectangle of the scene:
    // `opts` `ops`, `px` (`{ w, h }` it was drawn at), `under` (the cells
    // drawn there go over it), `clip` (the part that shows).
    // @param rect types.Rect
    // @param opts types.ScenePictureOptions
    // @return nil
    api.set(
        "scene_picture",
        lua.create_function(guarded!("scene_picture", move |lua, (rect, opts): (LuaValue, LuaValue)| {
            let rect: Area = from_lua(lua, rect)?;
            let opts: PictureOpts = from_lua(lua, opts)?;
            let mut scenes = sh.scenes.borrow_mut();
            let Some(b) = scenes.building.as_mut() else {
                return Err(mlua::Error::runtime("scene_picture without scene_begin"));
            };
            let key = b.name(format!("p{},{}", rect.x, rect.y));
            let picture = Picture { ops: Some(opts.ops), blob: None, px: opts.px, under: opts.under };
            let mut node = Node::new(key, Kind::Picture(picture), rect.units());
            node.clip = opts.clip.map(|c| c.units());
            b.scene.push(None, node);
            Ok(())
        }))?,
    )?;
    let sh = shared.clone();
    // The scene made, kept as what `client` has of the window `id`: the
    // patch (JSON) that brings what it had up to it, pushed to it as a
    // `scene.patch` event (unless it is 0, the instance's own); nil when
    // nothing changed. A second result false: the connection is gone.
    // @return string, boolean
    api.set(
        "scene_end",
        lua.create_function(guarded!("scene_end", move |_, (client, id): (u64, String)| {
            let patch = sh.scenes.borrow_mut().end(client, &id);
            let Some(patch) = patch else { return Ok((None, true)) };
            let sent = client == 0 || sh.clients.send(client, format!(r#"{{"event":"scene.patch","payload":{patch}}}"#));
            if !sent {
                sh.scenes.borrow_mut().forget(client, None);
            }
            Ok((Some(patch), sent))
        }))?,
    )?;
    let sh = shared.clone();
    // Forget what `client` was sent of the window `id`, or of all of them:
    // its next scene of one is sent whole.
    // @return nil
    api.set(
        "scene_forget",
        lua.create_function(guarded!("scene_forget", move |_, (client, id): (u64, Option<String>)| {
            sh.scenes.borrow_mut().forget(client, id.as_deref());
            Ok(())
        }))?,
    )?;
    let sh = shared.clone();
    // What `client` has of the window `id`, lowered to cells: as
    // `ui_view_snapshot` gives a view, rows of runs of one style.
    // @return types.ViewSnapshot
    api.set(
        "scene_cells",
        lua.create_function(guarded!("scene_cells", move |lua, (client, id): (u64, String)| {
            let scenes = sh.scenes.borrow();
            let Some(scene) = scenes.kept.get(&(client, id)) else { return Ok(LuaValue::Nil) };
            let (fg, bg) = scene.colors();
            let cells = scene.to_cells();
            let snapshot = serde_json::json!({
                "width": cells.width, "height": cells.height,
                "fg": scene.fg, "bg": scene.bg, "rows": cells.runs(fg, bg),
                "cursor": scene.cursor.map(|[x, y]| serde_json::json!({ "x": x, "y": y })),
            });
            to_lua(lua, &snapshot)
        }))?,
    )?;
    let sh = shared.clone();
    // A drawing that `client` got from paw, by its content key.
    // @return {types.CanvasOp}
    api.set(
        "scene_blob",
        lua.create_function(guarded!("scene_blob", move |lua, (client, key): (u64, String)| {
            let scenes = sh.scenes.borrow();
            match scenes.blobs.get(&client).and_then(|b| b.get(&key)) {
                Some(ops) => to_lua(lua, ops),
                None => Err(mlua::Error::runtime(format!("no drawing `{key}`"))),
            }
        }))?,
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use paw_scene::cells::Color;
    use paw_scene::Patch;

    fn building(w: f32, h: f32) -> Scenes {
        let scene = Scene::new([w, h]);
        Scenes { building: Some(Building::new(scene, true)), ..Scenes::default() }
    }

    fn all(w: i32, h: i32) -> Rect {
        Rect { x: 0, y: 0, w, h }
    }

    #[test]
    fn writes_are_kept_as_named_nodes_and_unseen_ones_left_out() {
        let mut s = building(10.0, 3.0);
        let red = Style { fg: Some(Color::Rgb(255, 0, 0)), ..Style::default() };
        s.fill(all(10, 3), all(10, 3), Some(' '), Style::default());
        s.text(all(10, 3), 1, 1, "hi", red);
        s.text(all(10, 3), 1, 1, "ho", red);
        // Cut by a sub-buffer: kept with its cut.
        s.text(Rect { x: 0, y: 2, w: 4, h: 1 }, 2, 2, "long text", Style::default());
        // Outside what it is cut to, or off the scene: nothing.
        s.text(Rect { x: 0, y: 0, w: 4, h: 1 }, 5, 0, "far", Style::default());
        s.fill(all(10, 3), Rect { x: 0, y: 5, w: 2, h: 2 }, None, red);
        let patch: Patch = serde_json::from_str(&s.end(7, "3").unwrap()).unwrap();
        let keys: Vec<&str> = patch.set.iter().map(|n| n.key.as_str()).collect();
        assert_eq!(keys, vec!["f0,0,10,3", "t1,1", "t1,1#2", "t2,2"]);
        assert!(patch.full, "the first scene of a window is sent whole");
        assert_eq!(patch.set[3].clip, Some([0.0, 2.0, 4.0, 1.0]));
        assert_eq!(patch.set[1].clip, None, "cut to the whole scene is no cut");
    }

    #[test]
    fn a_window_drawn_again_alike_says_nothing_and_a_change_says_only_itself() {
        let mut s = Scenes::default();
        let draw = |s: &mut Scenes, word: &str| {
            s.building = Some(Building::new(Scene::new([10.0, 2.0]), true));
            s.text(all(10, 2), 0, 0, "title", Style::default());
            s.text(all(10, 2), 0, 1, word, Style::default());
            s.end(1, "w")
        };
        assert!(draw(&mut s, "one").is_some());
        assert_eq!(draw(&mut s, "one"), None);
        let patch: Patch = serde_json::from_str(&draw(&mut s, "two").unwrap()).unwrap();
        assert_eq!((patch.full, patch.set.len(), patch.set[0].key.as_str()), (false, 1, "t0,1"));
        // Forgotten, it is sent whole again.
        s.forget(1, Some("w"));
        let patch: Patch = serde_json::from_str(&draw(&mut s, "two").unwrap()).unwrap();
        assert!(patch.full);
    }

    #[test]
    fn writes_while_a_role_is_open_are_its_cells_and_a_frontend_that_draws_it_gets_none() {
        let draw = |s: &mut Scenes| {
            let scene = Scene::new([10.0, 4.0]);
            s.building = Some(Building::new(scene, true));
            s.text(all(10, 4), 0, 0, "Mixer", Style::default());
            let b = s.building.as_mut().unwrap();
            let props = serde_json::json!({ "value": -6 });
            let mut node = Node::new("fader@4,1", Kind::Role { role: "fader".into(), props }, [4.0, 1.0, 3.0, 3.0]);
            node.hit = Some(serde_json::json!({ "kind": "fader", "part": 1 }));
            b.push(node);
            let map = Map::UNITS.inside(&b.scene.nodes["fader@4,1"]);
            b.open.push(Open { key: "fader@4,1".into(), map, with: false });
            s.fill(all(10, 4), Rect { x: 5, y: 1, w: 1, h: 3 }, Some('│'), Style::default());
            s.text(all(10, 4), 4, 2, "━━━", Style::default());
            s.building.as_mut().unwrap().open.pop();
        };
        let mut s = Scenes::default();
        draw(&mut s);
        let patch: Patch = serde_json::from_str(&s.end(1, "w").unwrap()).unwrap();
        let keys: Vec<&str> = patch.set.iter().map(|n| n.key.as_str()).collect();
        assert_eq!(keys, vec!["t0,0", "fader@4,1", "fader@4,1/f1,0,1,3", "fader@4,1/t0,1"]);
        assert_eq!(patch.set[3].rect, [0.0, 1.0, 3.0, 1.0], "placed from the role's corner");
        let mut kept = Scene::default();
        kept.apply(&patch);
        assert_eq!(kept.to_cells().cells[2 * 10 + 4].ch, '━', "its cells where it drew them");
        assert_eq!(kept.hit([5.5, 2.5]).map(|h| h.hit["part"].clone()), Some(serde_json::json!(1)));
        // A frontend that draws faders itself is sent the role alone.
        s.roles.insert(2, ["fader".to_string()].into());
        draw(&mut s);
        let patch: Patch = serde_json::from_str(&s.end(2, "w").unwrap()).unwrap();
        let keys: Vec<&str> = patch.set.iter().map(|n| n.key.as_str()).collect();
        assert_eq!(keys, vec!["t0,0", "fader@4,1"]);
        s.forget(2, None);
        assert!(!s.roles.contains_key(&2), "forgotten with the connection");
    }

    fn opts(value: Value) -> OpenOpts {
        serde_json::from_value(value).unwrap()
    }

    #[test]
    fn nodes_put_into_a_plane_are_in_its_domain_with_their_cells_and_keep_the_order_drawn() {
        let mut s = building(20.0, 6.0);
        // A roll: beats along x from beat 4, two units a beat; pitches up,
        // pitch 64 on the plane's first row.
        let axes = serde_json::json!({ "x": { "domain": "beat", "from": 4, "per": 2 }, "y": { "domain": "pitch", "from": 65, "per": -1 } });
        let made = s.open([2.0, 1.0, 16.0, 4.0], opts(serde_json::json!({ "plane": axes, "key": "roll", "hit": { "kind": "grid" } })));
        assert_eq!(made, Ok(true));
        s.close();
        // A note from beat 5.25, a beat long, on pitch 62: units 4.5 to 6.5
        // along, the plane's third row; a terminal snaps it to columns 5
        // and 6 (rounding its edges), where its cells are written.
        let note = |s: &mut Scenes, start: f32, key: &str| {
            let o = opts(serde_json::json!({ "into": "roll", "role": "note", "key": key, "hit": { "kind": "note" } }));
            assert_eq!(s.open([start, 62.0, 1.0, 1.0], o), Ok(true));
            let x = (2.0 + (start - 4.0) * 2.0 + 0.5).floor() as i32;
            s.fill(all(20, 6), Rect { x, y: 3, w: 2, h: 1 }, Some('█'), Style::default());
            s.close();
        };
        note(&mut s, 5.25, "n1");
        // Drawn over the plane after it: what was put in it before stays under.
        s.fill(all(20, 6), Rect { x: 0, y: 3, w: 20, h: 1 }, None, Style { fg: Some(Color::Indexed(1)), ..Style::default() });
        note(&mut s, 8.25, "n2");
        let patch: Patch = serde_json::from_str(&s.end(1, "w").unwrap()).unwrap();
        let root = patch.root.clone().unwrap();
        assert_eq!(root, vec!["roll".to_string(), "f0,3,20,1".into(), "roll#2".into()], "the plane goes on after what covered it");
        let n1 = patch.set.iter().find(|n| n.key == "roll/n1").expect("the note in the plane");
        assert_eq!(n1.rect, [5.25, 62.0, 1.0, 1.0], "in the plane's domain");
        // Its cells in its own space: a quarter beat in (column 5 is unit
        // 5, the note starts at 4.5), a beat wide, named by their cell.
        let cells = patch.set.iter().find(|n| n.key.starts_with("roll/n1/")).expect("its cells");
        assert_eq!((cells.key.as_str(), cells.rect), ("roll/n1/f1,-1,2,1", [0.25, 0.0, 1.0, 1.0]));
        let mut kept = Scene::default();
        kept.apply(&patch);
        let row: String = kept.to_cells().cells[3 * 20..4 * 20].iter().map(|c| c.ch).collect();
        assert_eq!(row, "     ██    ██       ", "each note's cells where the terminal wrote them");
        let on = kept.hit([5.0, 3.5]).expect("the note under the pointer");
        assert_eq!((on.key.as_str(), on.at), ("roll/n1", [5.5, 62.5]), "where in the plane's domain");
        assert_eq!(on.rect, [4.5, 3.0, 2.0, 1.0], "the note as it is, not as a terminal snaps it");
        let grid = kept.hit([15.0, 1.5]).expect("the empty grid");
        assert_eq!(grid.hit["kind"], "grid");
        assert_eq!(s.open([0.0, 0.0, 1.0, 1.0], opts(serde_json::json!({ "into": "none" }))), Ok(false), "no such plane");
    }

    #[test]
    fn a_big_drawing_goes_by_its_content_key_and_is_dropped_with_its_scene() {
        let mut s = building(10.0, 4.0);
        let ops = Value::Array((0..2000).map(|i| serde_json::json!(["r", i, 0, 1, 1, "#ffffff", "", 1, 0])).collect());
        let picture = Picture { ops: Some(ops.clone()), blob: None, px: [80.0, 68.0], under: false };
        s.building.as_mut().unwrap().scene.push(None, Node::new("p0,0", Kind::Picture(picture), [0.0, 0.0, 10.0, 4.0]));
        let patch: Patch = serde_json::from_str(&s.end(2, "w").unwrap()).unwrap();
        let Kind::Picture(sent) = &patch.set[0].kind else { panic!("not a picture") };
        let key = sent.blob.clone().expect("sent by its key");
        assert_eq!(sent.ops, None);
        assert_eq!(s.blobs[&2][&key], ops);
        s.forget(2, None);
        assert!(!s.blobs.contains_key(&2), "nothing kept for a connection that has no scenes");
    }
}
