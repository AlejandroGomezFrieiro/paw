//! The roles the window paints itself (runtime/lua/paw/roles/widgets.lua):
//! a scene's role node is a rectangle the view laid out in cells and the
//! props that say what it shows; here it becomes a widget drawn in that
//! rectangle, crisp at any size. Gestures on it go back to the kernel as
//! any pointer event over a scene does (crate::scene): the view's hit
//! regions say what they mean, in both frontends. A meter bound to a
//! track's (`bind`, `meter:<id>`) moves with `scene.live`, with no new
//! scene.

use std::str::FromStr;

use egui::{Align2, Color32, CornerRadius, Id, Painter, Pos2, Rect, Sense, Stroke, StrokeKind, Ui, pos2, vec2};
use paw_scene::props::{self, *};
use paw_scene::{Kind, Node};
use serde_json::Value;

use crate::theme::{T_BASE, T_SMALL, alpha, hex, mix, mono_medium, semi, th};
use crate::{timeline, widgets};

/// A role this window paints, read once from a role node's name (the
/// `role` of the scene's node, as runtime/lua/paw/roles names it). Each
/// has its props in paw_scene::props (`LabelProps` for `Label`, and so on),
/// read from the node as it is painted. A role not named here is drawn as
/// the cells the view lowered it to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Role {
    Label,
    Button,
    Switch,
    Knob,
    Fader,
    Meter,
    Peak,
    Chip,
    Note,
    Keyboard,
    Playhead,
    Scrollbar,
    Param,
    Power,
    Band,
    Clip,
    Beats,
    Hmeter,
    Curve,
    Trackhead,
    Recording,
}

/// A role's name that this window does not paint.
#[derive(Debug, PartialEq, Eq)]
pub struct UnknownRole;

impl Role {
    /// The roles this window paints: it says so when it watches scenes,
    /// and is sent them without their cells.
    pub const ALL: [Role; 21] = [
        Role::Label,
        Role::Button,
        Role::Switch,
        Role::Knob,
        Role::Fader,
        Role::Meter,
        Role::Peak,
        Role::Chip,
        Role::Note,
        Role::Keyboard,
        Role::Playhead,
        Role::Scrollbar,
        Role::Param,
        Role::Power,
        Role::Band,
        Role::Clip,
        Role::Beats,
        Role::Hmeter,
        Role::Curve,
        Role::Trackhead,
        Role::Recording,
    ];

    /// Its name in a scene.
    pub fn name(self) -> &'static str {
        match self {
            Role::Label => "label",
            Role::Button => "button",
            Role::Switch => "switch",
            Role::Knob => "knob",
            Role::Fader => "fader",
            Role::Meter => "meter",
            Role::Peak => "peak",
            Role::Chip => "chip",
            Role::Note => "note",
            Role::Keyboard => "keyboard",
            Role::Playhead => "playhead",
            Role::Scrollbar => "scrollbar",
            Role::Param => "param",
            Role::Power => "power",
            Role::Band => "band",
            Role::Clip => "clip",
            Role::Beats => "beats",
            Role::Hmeter => "hmeter",
            Role::Curve => "curve",
            Role::Trackhead => "trackhead",
            Role::Recording => "recording",
        }
    }

    /// The role of a node, if it is one this window paints.
    pub fn of(node: &Node) -> Option<Role> {
        match &node.kind {
            Kind::Role { role, .. } => role.parse().ok(),
            _ => None,
        }
    }

    /// Whether it paints over all of its rectangle: what is under it is not
    /// drawn.
    pub fn opaque(self) -> bool {
        matches!(self, Role::Beats | Role::Trackhead)
    }
}

impl FromStr for Role {
    type Err = UnknownRole;

    fn from_str(name: &str) -> Result<Role, UnknownRole> {
        Role::ALL.into_iter().find(|role| role.name() == name).ok_or(UnknownRole)
    }
}

/// A colour named by the palette (`tone`), else `or`.
fn tone(tone: Option<&str>, or: Color32) -> Color32 {
    tone.and_then(|t| th().named(t)).unwrap_or(or)
}

/// How far up a meter a linear level reaches, from 0 to 1 over 60 dB, as
/// the terminal's meters have it (`paw.draw.level`).
fn level(peak: f32) -> f32 {
    ((20.0 * peak.max(1e-6).log10() + 60.0) / 60.0).clamp(0.0, 1.0)
}

/// The text of a role, in a font that fits its row.
fn font_for(rect: Rect, bold: bool) -> egui::FontId {
    let size = (rect.height() * 0.68).clamp(8.0, T_SMALL + 1.0);
    if bold { semi(size) } else { crate::theme::sans(size) }
}

/// What a role is called (its `label`), for whoever reads the window
/// without seeing it; said each frame, painted or not.
pub fn name(ui: &Ui, id: Id, node: &Node, rect: Rect) {
    if let Kind::Role { props, .. } = &node.kind
        && let Some(name) = props::parse::<RoleProps>(props).label
    {
        let response = ui.interact(rect, id, Sense::hover());
        widgets::name(&response, name);
    }
}

/// Paint the node `node`, of the role `role`, over `rect` (points), on a
/// scene whose cells are `cell` points, with the live values the kernel
/// last sent; `id` is its own in the window.
#[allow(clippy::too_many_arguments)]
pub fn paint(ui: &Ui, painter: &Painter, id: Id, node: &Node, role: Role, rect: Rect, cell: (f32, f32), live: &Value) {
    let Kind::Role { props, .. } = &node.kind else { return };
    name(ui, id, node, rect);
    let under = ui.rect_contains_pointer(rect);
    match role {
        Role::Label => label(ui, painter, rect, &props::parse(props), cell),
        Role::Button => button(ui, painter, rect, &props::parse(props), under),
        Role::Switch => switch(painter, rect, &props::parse(props), under),
        Role::Knob => knob(painter, rect, &props::parse(props), under),
        Role::Power => power(painter, rect, &props::parse(props), under),
        Role::Band => band(painter, rect, &props::parse(props)),
        Role::Note => note(ui, painter, rect, &props::parse(props), under),
        Role::Keyboard => keyboard(painter, rect, &props::parse(props), cell.1),
        Role::Scrollbar => scrollbar(painter, rect, &props::parse(props), under),
        Role::Fader => fader(painter, rect, &props::parse(props), under, cell.1),
        Role::Chip => chip(ui, painter, rect, &props::parse(props)),
        // The arrange view's (crate::timeline).
        Role::Clip => timeline::clip(ui, painter, &props::parse(props), rect, cell),
        Role::Beats => timeline::ground(painter, &props::parse(props), rect, cell),
        Role::Curve => timeline::curve(painter, &props::parse(props), rect, cell),
        Role::Trackhead => timeline::trackhead(ui, painter, &props::parse(props), rect),
        Role::Param | Role::Playhead | Role::Meter | Role::Peak | Role::Hmeter | Role::Recording => paint_live(painter, node, role, rect, cell, live, under),
    }
}

/// A line of text, in the window's monospace font unless it asks for words
/// (`sans`) or a heading (`title`); cut to its rectangle.
fn label(ui: &Ui, painter: &Painter, rect: Rect, p: &LabelProps, cell: (f32, f32)) {
    let t = th();
    let align = match p.align {
        Some("right") => Align2::RIGHT_CENTER,
        Some("center") => Align2::CENTER_CENTER,
        _ => Align2::LEFT_CENTER,
    };
    let at = match align {
        Align2::RIGHT_CENTER => rect.right_center(),
        Align2::CENTER_CENTER => rect.center(),
        _ => rect.left_center(),
    };
    let size = (rect.height() * 0.7).clamp(8.0, T_SMALL + 1.0);
    let font = match p.font {
        Some("sans") => crate::theme::sans(size + 0.5),
        Some("title") => semi((rect.height() * 0.72).clamp(8.0, T_BASE)),
        _ => mono_medium(size),
    };
    let colour = tone(p.tone, t.text_2);
    // Words may be a little wider than the cells they stand in: up to a
    // cell more, which a view leaves free after a heading.
    let mut said = p.text.unwrap_or("").trim_end().to_string();
    if p.capital
        && let Some(first) = said.chars().next()
    {
        said = first.to_uppercase().chain(said.chars().skip(1)).collect();
    }
    let room = rect.width() + if p.font.is_some() { cell.0 } else { 2.0 };
    let shown = widgets::elide(ui, &said, font.clone(), room);
    let drawn = painter.text(at, align, shown, font, colour);
    if p.strike {
        painter.hline(drawn.x_range(), drawn.center().y, Stroke::new(1.0, colour));
    }
}

/// A button. A quiet one shows a face only under the pointer or when on;
/// one that opens a menu has a caret, drawn, for the terminal's `▾`.
fn button(ui: &Ui, painter: &Painter, rect: Rect, p: &ButtonProps, under: bool) {
    let t = th();
    let (on, menu) = (p.on, p.menu);
    let face = if under { t.control_hover } else if p.quiet { Color32::TRANSPARENT } else { t.control };
    let mut shape = rect.shrink2(vec2(1.0, 2.0));
    painter.rect_filled(shape, CornerRadius::same(4), if on { alpha(t.select, 0.85) } else { face });
    let colour = if on { t.surface } else if p.off { t.text_3 } else { tone(p.tone, t.text) };
    let font = font_for(rect, false);
    let whole = p.words.or(p.text).unwrap_or("");
    // An icon in place of the glyph that stands for it in cells: a text of
    // one character is that glyph alone, a longer one the words after it.
    if let Some(icon) = p.icon.and_then(icon_named) {
        let words = whole.trim().trim_start_matches(|c: char| !c.is_alphanumeric()).trim();
        let side = (shape.height() - 4.0).clamp(8.0, 12.0);
        if whole.trim().chars().count() <= 1 || words.is_empty() {
            widgets::icon_on(painter, Rect::from_center_size(shape.center(), vec2(side, side)), icon, colour);
            return;
        }
        widgets::icon_on(painter, Rect::from_min_size(pos2(shape.left() + 5.0, shape.center().y - side / 2.0), vec2(side, side)), icon, colour);
        shape.min.x += side + 4.0;
        let room = shape.width() - 10.0;
        let shown = widgets::elide(ui, words, font.clone(), room);
        painter.text(pos2(shape.left() + 3.0, shape.center().y), Align2::LEFT_CENTER, shown, font, colour);
        return;
    }
    let label = if menu { whole.trim().trim_end_matches(['▾', 'v']).trim_end() } else { whole.trim() };
    // A small one keeps a narrow margin; a menu too narrow for its words
    // and its caret shows the words alone.
    let margin = if shape.width() < 30.0 { 2.0 } else if shape.width() < 40.0 { 4.0 } else { 10.0 };
    let caret = menu && (label.is_empty() || widgets::text_width(ui, label, font.clone()) <= shape.width() - 16.0);
    let room = shape.width() - if caret { 16.0 } else if menu { 6.0 } else { margin };
    let shown = widgets::elide(ui, label, font.clone(), room);
    let centred = !menu && widgets::text_width(ui, &shown, font.clone()) < room;
    if centred {
        painter.text(shape.center(), Align2::CENTER_CENTER, shown, font, colour);
    } else {
        painter.text(pos2(shape.left() + if menu { 3.0 } else { 5.0 }, shape.center().y), Align2::LEFT_CENTER, shown, font, colour);
    }
    if caret {
        let (x, y) = (shape.right() - 10.0, shape.center().y);
        painter.add(egui::Shape::convex_polygon(vec![pos2(x - 3.5, y - 1.5), pos2(x + 3.5, y - 1.5), pos2(x, y + 2.5)], t.text_2, Stroke::NONE));
    }
}

/// A switch, lit in its `tone` when on: an icon in place of its letter,
/// where it names one.
fn switch(painter: &Painter, rect: Rect, p: &SwitchProps, under: bool) {
    let t = th();
    let on = p.on;
    let lit = tone(p.tone, t.select);
    let side = rect.width().min(rect.height()).max(4.0);
    let shape = Rect::from_center_size(rect.center(), vec2(rect.width().max(side) - 1.0, rect.height() - 2.0));
    let face = if on { lit } else if under { t.control_hover } else { t.control };
    painter.rect_filled(shape, CornerRadius::same(3), face);
    let ink = if on { t.on_hue } else { t.text_2 };
    match p.icon.and_then(icon_named) {
        Some(icon) => {
            let side = (shape.height() - 4.0).clamp(8.0, 12.0);
            widgets::icon_on(painter, Rect::from_center_size(shape.center(), vec2(side, side)), icon, ink);
        }
        None => {
            let letter = p.letter.unwrap_or("");
            painter.text(shape.center(), Align2::CENTER_CENTER, letter, semi((rect.height() * 0.6).clamp(8.0, T_SMALL)), ink);
        }
    }
}

/// A pan. A round one is a knob turned from the middle, its pointer where
/// the sound sits; else a rail across, the middle marked, a bar from the
/// middle to where the sound sits and a thumb there.
fn knob(painter: &Painter, rect: Rect, p: &KnobProps, under: bool) {
    let t = th();
    let value = (p.value as f32).clamp(-1.0, 1.0);
    if p.round {
        let r = (rect.height().min(rect.width()) / 2.0 - 1.0).max(3.0);
        let centre = pos2(rect.left() + r + 1.0, rect.center().y);
        painter.circle(centre, r, if under { t.control_hover } else { t.control }, Stroke::new(1.0, t.divider));
        let turn = value * 135f32.to_radians();
        let at = |d: f32| centre + vec2(turn.sin(), -turn.cos()) * d;
        painter.line_segment([at(r * 0.25), at(r - 1.5)], Stroke::new(2.0, if value.abs() > 1e-3 { t.select } else { t.text }));
        return;
    }
    let y = rect.center().y;
    let (left, right) = (rect.left() + 3.0, rect.right() - 3.0);
    let middle = (left + right) / 2.0;
    let at = middle + value * (right - left) / 2.0;
    painter.hline(left..=right, y, Stroke::new(2.0, t.well));
    painter.vline(middle, (y - 3.0)..=(y + 3.0), Stroke::new(1.0, t.text_3));
    painter.hline(middle.min(at)..=middle.max(at), y, Stroke::new(2.0, t.select));
    painter.circle_filled(pos2(at, y), (rect.height() * 0.28).clamp(3.0, 6.0), if under { t.bright } else { t.thumb });
}

/// A power button, lit while the device plays.
fn power(painter: &Painter, rect: Rect, p: &PowerProps, under: bool) {
    let t = th();
    let on = p.on;
    let shape = Rect::from_center_size(rect.center(), vec2(rect.height().max(18.0).min(rect.width()), rect.height() - 2.0));
    let face = if on { alpha(t.select, 0.85) } else if under { t.control_hover } else { t.control };
    painter.rect_filled(shape, CornerRadius::same(4), face);
    let side = (shape.height() - 5.0).clamp(8.0, 12.0);
    widgets::icon_on(painter, Rect::from_center_size(shape.center(), vec2(side, side)), crate::icons::POWER, if on { t.surface } else { t.text_3 });
}

/// A card's heading: a band across, a shade lighter than the panel; tinted
/// where the keyboard's cursor is.
fn band(painter: &Painter, rect: Rect, p: &BandProps) {
    let t = th();
    let shape = rect.shrink2(vec2(1.0, 0.5));
    let face = if p.selected { mix(t.card, t.select, 0.72) } else if p.off { alpha(t.card, 0.6) } else { t.card };
    painter.rect_filled(shape, CornerRadius::same(3), face);
    painter.hline(shape.x_range(), shape.top() + 0.5, Stroke::new(1.0, alpha(t.card_line, 0.8)));
}

/// A track's name on its colour, with its number; outlined when chosen.
fn chip(ui: &Ui, painter: &Painter, rect: Rect, p: &ChipProps) {
    let t = th();
    let colour = p.color.and_then(hex).unwrap_or(t.control);
    painter.rect_filled(rect, CornerRadius::ZERO, colour);
    let font = font_for(rect, true);
    let mut left = rect.left() + 4.0;
    if let Some(n) = p.number {
        let number = n.to_string();
        painter.text(pos2(left, rect.center().y), Align2::LEFT_CENTER, &number, font.clone(), alpha(t.on_hue, 0.6));
        left += widgets::text_width(ui, &number, font.clone()) + 4.0;
    }
    let shown = widgets::elide(ui, p.text.unwrap_or(""), font.clone(), rect.right() - 4.0 - left);
    painter.text(pos2((left + rect.right() - 4.0) / 2.0, rect.center().y), Align2::CENTER_CENTER, shown, font, t.on_hue);
    if p.selected {
        painter.rect_stroke(rect, CornerRadius::ZERO, Stroke::new(1.0, Color32::WHITE), StrokeKind::Inside);
    }
}

/// Paint a role that the live values can move (`bind`): the playhead, a
/// meter, a peak, a parameter, a level across a row, a take being
/// recorded. It needs no `Ui`: the window paints these again by themselves
/// while only the live values change (crate::runner). Nothing for another
/// role.
pub fn paint_live(painter: &Painter, node: &Node, role: Role, rect: Rect, cell: (f32, f32), live: &Value, under: bool) {
    let Kind::Role { props, .. } = &node.kind else { return };
    let bind = node.bind.as_deref();
    match role {
        Role::Param => param(painter, rect, &props::parse(props), bind, live, cell, under),
        Role::Playhead => playhead(painter, rect, &props::parse(props), bind, live, cell),
        Role::Meter => meter(painter, rect, &props::parse(props), bind, live),
        Role::Peak => peak(painter, rect, &props::parse(props), bind, live, under),
        Role::Hmeter => timeline::hmeter(painter, &props::parse(props), bind, live, rect, under),
        Role::Recording => timeline::recording(painter, &props::parse(props), bind, live, rect, cell),
        _ => {}
    }
}

/// The loudest of late in a well, which turns red with the clip light.
fn peak(painter: &Painter, rect: Rect, p: &MeterProps, bind: Option<&str>, live: &Value, under: bool) {
    let t = th();
    let (hold, clipped) = held(p.hold, p.clipped, bind, live);
    let db = 20.0 * hold.max(1e-6).log10();
    let said = crate::model::decibels(db);
    let well = rect.shrink2(vec2(0.0, 1.0));
    painter.rect_filled(well, CornerRadius::same(2), if clipped { alpha(t.meter_clip, 0.25) } else if under { t.control_hover } else { t.well });
    let colour = if clipped { t.meter_clip } else if db > -0.1 { t.meter_hot } else { t.text_2 };
    let size = (rect.height() * 0.7).clamp(8.0, T_SMALL + 1.0);
    painter.text(well.right_center() - vec2(3.0, 0.0), Align2::RIGHT_CENTER, said, mono_medium(size), colour);
}

/// A note where it is between cells: its track's colour, deeper the harder
/// it is played; light with a white edge when chosen, outlined where the
/// keyboard's cursor is; one being drawn see-through with a bright edge.
/// Its name inside when there is room.
fn note(ui: &Ui, painter: &Painter, rect: Rect, p: &NoteProps, under: bool) {
    let t = th();
    let colour = p.color.and_then(hex).unwrap_or(t.select);
    let velocity = (p.velocity as f32 / 127.0).clamp(0.0, 1.0);
    // A row's height less a pixel above and below, a pixel short of where
    // the next note starts, never thinner than a mark.
    let shape = Rect::from_min_max(rect.min + vec2(0.0, 1.0), rect.max - vec2(1.0, 1.0));
    let shape = if shape.width() < 4.0 { Rect::from_min_size(shape.min, vec2(4.0, shape.height())) } else { shape };
    let dark = Color32::from_rgb(0x12, 0x13, 0x16);
    let (face, edge, ink) = if p.ghost {
        (alpha(colour, 0.45), Stroke::new(1.0, Color32::WHITE), Color32::WHITE)
    } else if p.pending {
        (alpha(colour, 0.35), Stroke::new(1.0, colour), t.text)
    } else if p.selected {
        (mix(colour, Color32::WHITE, 0.7), Stroke::new(1.0, Color32::WHITE), dark)
    } else if under {
        (mix(colour, Color32::WHITE, 0.85), Stroke::new(1.0, Color32::from_black_alpha(0x60)), dark)
    } else {
        // Loud at the track's full colour, quiet ones fainter.
        (mix(colour, t.surface, 0.45 + 0.55 * velocity), Stroke::new(1.0, Color32::from_black_alpha(0x60)), dark)
    };
    painter.rect(shape, CornerRadius::same(2), face, edge, StrokeKind::Inside);
    if p.cursor {
        painter.rect_stroke(shape.expand(1.0), CornerRadius::same(3), Stroke::new(1.5, t.play), StrokeKind::Outside);
    }
    // Its name inside, when the name fits.
    let label = p.label.unwrap_or("");
    let font = semi((rect.height() * 0.62).clamp(8.0, T_SMALL));
    if !label.is_empty() && widgets::text_width(ui, label, font.clone()) + 6.0 <= shape.width() {
        painter.with_clip_rect(shape.intersect(painter.clip_rect())).text(pos2(shape.left() + 3.0, shape.center().y), Align2::LEFT_CENTER, label, font, ink);
    }
    bend_line(painter, rect, p, if p.pending { colour } else { ink });
}

/// A note's own pitch bend: a line along the note that leaves it where the
/// bend starts and reaches the row of the pitch it bends to at its end, a
/// row a semitone.
fn bend_line(painter: &Painter, rect: Rect, p: &NoteProps, colour: Color32) {
    if p.bend == 0.0 || !p.bend.is_finite() {
        return;
    }
    let y = rect.center().y;
    let from = rect.left() + rect.width() * p.bend_at.clamp(0.0, 1.0) as f32;
    let to = pos2(rect.right(), y - p.bend as f32 * rect.height());
    let stroke = Stroke::new(1.5, colour);
    painter.line_segment([pos2(rect.left(), y), pos2(from, y)], stroke);
    painter.line_segment([pos2(from, y), to], stroke);
    painter.circle_filled(to, 2.0, colour);
}

const NAMES: [&str; 12] = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"];

fn pitch_name(pitch: i64) -> String {
    format!("{}{}", NAMES[pitch.rem_euclid(12) as usize], pitch.div_euclid(12) - 1)
}

fn is_black(pitch: i64) -> bool {
    matches!(pitch.rem_euclid(12), 1 | 3 | 6 | 8 | 10)
}

/// A piano down the left of a roll, `per` rows of `row` points a pitch
/// from `top` down: white keys and black ones, a line where E meets F and B
/// meets C, each C named; the cursor's key lit and named, the keys sounding
/// at the cursor dotted, what the instrument or a module calls a key on it.
fn keyboard(painter: &Painter, rect: Rect, p: &KeyboardProps, row: f32) {
    let t = th();
    painter.rect_filled(rect, CornerRadius::ZERO, t.key_white);
    let top = p.top.unwrap_or(127);
    let cursor = p.cursor.unwrap_or(-1);
    let (names, labels, sounding) = (&p.names, &p.labels, &p.sounding);
    // A key is `per` rows of the grid tall (the roll's vertical zoom).
    let row = row * p.per.unwrap_or(1).clamp(1, 8) as f32;
    let rows = (rect.height() / row.max(1.0)).round() as i64;
    let size = (row * 0.62).clamp(8.0, T_SMALL);
    for r in 0..rows {
        let pitch = top - r;
        if pitch < 0 {
            break;
        }
        let key = Rect::from_min_size(pos2(rect.left(), rect.top() + r as f32 * row), vec2(rect.width(), row));
        if pitch.rem_euclid(12) == 0 || pitch.rem_euclid(12) == 5 {
            painter.hline(key.x_range(), key.bottom() - 0.5, Stroke::new(1.0, t.key_line));
        }
        if is_black(pitch) {
            painter.hline(key.x_range(), key.center().y, Stroke::new(1.0, t.key_line));
            painter.rect_filled(Rect::from_min_size(key.min, vec2(rect.width() * 0.6, row)), CornerRadius::ZERO, t.key_black);
        }
        let said = names.iter().chain(labels).find(|k| k.pitch == pitch).map(|k| k.name.to_string());
        if pitch == cursor {
            painter.rect_filled(key, CornerRadius::ZERO, t.play);
            painter.text(pos2(key.left() + 4.0, key.center().y), Align2::LEFT_CENTER, said.unwrap_or_else(|| pitch_name(pitch)), semi(size), t.on_hue);
        } else if let Some(said) = said {
            let back = Rect::from_min_size(key.min, vec2(rect.width() * 0.75, row));
            painter.rect_filled(back, CornerRadius::ZERO, alpha(t.key_white, 0.9));
            painter.text(pos2(key.left() + 3.0, key.center().y), Align2::LEFT_CENTER, said, semi(size), t.on_hue);
        } else if pitch.rem_euclid(12) == 0 {
            painter.text(pos2(key.right() - 12.0, key.center().y), Align2::RIGHT_CENTER, pitch_name(pitch), semi(size), t.text_off);
        }
        if sounding.contains(&pitch) {
            let d = (row - 4.0).clamp(3.0, 7.0);
            painter.circle_filled(pos2(key.right() - 6.0, key.center().y), d / 2.0, crate::theme::mode_colour("i"));
        }
    }
    painter.vline(rect.right() - 0.5, rect.y_range(), Stroke::new(1.0, t.divider));
}

/// The playhead where the live values put it: a line down the grid on the
/// song's beat and a cap on the ruler, its first row.
fn playhead(painter: &Painter, rect: Rect, p: &PlayheadProps, bind: Option<&str>, live: &Value, (cw, ch): (f32, f32)) {
    let t = th();
    let at = match bind {
        Some("position") => live["position"].as_f64().or(p.at),
        _ => p.at,
    };
    let Some(at) = at else { return };
    // Along pieces of time (notation's systems, spaced by their notes):
    // `[from, to, x0, x1, top, bottom]` each, in points from the corner.
    if let Some(pieces) = &p.segments {
        let last = pieces.len().saturating_sub(1);
        for (i, piece) in pieces.iter().enumerate() {
            let n = |k: usize| piece.get(k).copied().unwrap_or(0.0);
            let (from, to) = (n(0), n(1));
            if at >= from && (at < to || (i == last && at <= to)) {
                let x = rect.left() + (n(2) + (n(3) - n(2)) * (at - from) / (to - from).max(1e-9)) as f32;
                let (top, bottom) = (rect.top() + n(4) as f32, rect.top() + n(5) as f32);
                let line = Rect::from_min_max(pos2(x.round() - 1.0, top.round()), pos2(x.round() + 1.0, bottom.round()));
                painter.rect_filled(line, CornerRadius::ZERO, t.play);
                return;
            }
        }
        return;
    }
    let (lo, hi) = (p.lo.unwrap_or(f64::MIN), p.hi.unwrap_or(f64::MAX));
    if at < lo || at > hi {
        return;
    }
    let x = rect.left() + ((p.view_beat(at) - p.from) * p.per.unwrap_or(1.0)) as f32 * cw;
    if x < rect.left() || x > rect.right() {
        return;
    }
    let ruler = rect.top() + ch;
    painter.vline(x.round() + 0.5, ruler..=rect.bottom(), Stroke::new(1.5, t.play));
    painter.add(egui::Shape::convex_polygon(vec![pos2(x - 4.5, ruler - 6.0), pos2(x + 4.5, ruler - 6.0), pos2(x, ruler)], t.play, Stroke::NONE));
}

/// A thin bar along a side of what scrolls, its thumb over what shows;
/// brighter under the pointer.
fn scrollbar(painter: &Painter, rect: Rect, p: &ScrollbarProps, under: bool) {
    let total = (p.total as f32).max(p.span as f32).max(1e-6);
    let (from, span) = (p.from as f32 / total, p.span as f32 / total);
    let face = Color32::from_white_alpha(if under { 0x50 } else { 0x24 });
    let thumb = if p.axis == Some("x") {
        let w = (rect.width() * span).max(24.0).min(rect.width());
        let x = (rect.left() + rect.width() * from).min(rect.right() - w);
        Rect::from_min_size(pos2(x, rect.bottom() - 6.0), vec2(w, 4.0))
    } else {
        let h = (rect.height() * span).max(24.0).min(rect.height());
        let y = (rect.top() + rect.height() * from).min(rect.bottom() - h);
        Rect::from_min_size(pos2(rect.right() - 6.0, y), vec2(4.0, h))
    };
    painter.rect_filled(thumb, CornerRadius::same(2), face);
}

/// A fader: a rail down the middle, 0 dB marked, a cap with a line across
/// it where the level is, at the place the terminal's cap is for it.
fn fader(painter: &Painter, rect: Rect, p: &FaderProps, under: bool, row: f32) {
    let t = th();
    let rows = (rect.height() / row.max(1.0)).round().max(1.0);
    let row_h = rect.height() / rows;
    // The middle of the row the cap is on, as a place along the travel.
    let y_of = |f: f32| rect.bottom() - row_h * (0.5 + f.clamp(0.0, 1.0) * (rows - 1.0));
    let x = rect.center().x;
    painter.vline(x, (rect.top() + row_h * 0.5)..=(rect.bottom() - row_h * 0.5), Stroke::new(3.0, t.well));
    if let Some(zero) = p.zero {
        let y = y_of(zero as f32);
        painter.hline((rect.left() + 2.0)..=(rect.right() - 2.0), y, Stroke::new(1.0, t.text_3));
    }
    let y = y_of(p.at as f32);
    let cap = Rect::from_center_size(pos2(x, y), vec2(rect.width() - 2.0, (row_h * 0.9).clamp(8.0, 16.0)));
    let face = if p.selected || under { t.bright } else { t.thumb };
    painter.rect_filled(cap, CornerRadius::same(2), face);
    painter.hline((cap.left() + 2.0)..=(cap.right() - 2.0), y, Stroke::new(1.0, t.surface));
}

/// The icon a button names (`icon`), as the cells' glyph stands for it.
fn icon_named(name: &str) -> Option<crate::icons::Icon> {
    use crate::icons::*;
    Some(match name {
        "up" => CARET_UP,
        "down" => CARET_DOWN,
        "remove" => X,
        "window" => ARROW_SQUARE_OUT,
        "plus" => PH_PLUS,
        "automate" => CHART_LINE,
        "learn" | "plugs" => PLUGS,
        "warning" => WARNING,
        "circle" => CIRCLE,
        "mic" => MICROPHONE,
        "speaker" => SPEAKER_HIGH,
        _ => return None,
    })
}

/// A parameter: a slider along its first `bar` cells, filled to where it
/// sits (from the middle for one either side of zero), a mark for each
/// choice of one that has a few, and its value at the right. Bound to a
/// parameter a lane moves (`param:<device>:<key>`), where it sits and what
/// it reads come from the live values.
fn param(painter: &Painter, rect: Rect, p: &ParamProps, bind: Option<&str>, live: &Value, (cw, _): (f32, f32), under: bool) {
    let t = th();
    let moved = bind.map(|b| &live["params"][b]).filter(|v| v.is_object());
    let (fraction, said) = match moved {
        Some(m) => (m["fraction"].as_f64().unwrap_or(0.0), m["text"].as_str().unwrap_or("")),
        None => (p.fraction, p.text.unwrap_or("")),
    };
    let fraction = fraction.clamp(0.0, 1.0) as f32;
    let dim = p.dim;
    let bar = (p.bar as f32 * cw).min(rect.width());
    let rail = Rect::from_min_size(pos2(rect.left() + 4.0, rect.center().y - 1.5), vec2((bar - 10.0).max(4.0), 3.0));
    painter.rect_filled(rail, CornerRadius::same(1), t.well);
    let at = rail.left() + rail.width() * fraction;
    let (x0, x1) = if p.centred { (rail.center().x.min(at), rail.center().x.max(at)) } else { (rail.left(), at) };
    let lit = if moved.is_some() { t.play } else if under { t.text_2 } else { t.select };
    painter.rect_filled(Rect::from_x_y_ranges(x0..=x1, rail.y_range()), CornerRadius::same(1), alpha(lit, if dim { 0.4 } else { 0.9 }));
    let steps = p.steps;
    if (2..=12).contains(&steps) {
        for i in 0..steps {
            let x = rail.left() + rail.width() * i as f32 / (steps - 1) as f32;
            painter.vline(x, (rail.top() - 2.0)..=(rail.bottom() + 2.0), Stroke::new(1.0, t.text_off));
        }
    }
    let thumb = Rect::from_center_size(pos2(at, rail.center().y), vec2(7.0, (rect.height() - 5.0).clamp(8.0, 13.0)));
    let face = if under { t.bright } else { t.thumb };
    painter.rect(thumb, CornerRadius::same(2), alpha(face, if dim { 0.6 } else { 1.0 }), Stroke::new(1.0, Color32::from_black_alpha(0x60)), StrokeKind::Inside);
    let size = (rect.height() * 0.68).clamp(8.0, T_SMALL);
    painter.text(pos2(rect.right() - 2.0, rect.center().y), Align2::RIGHT_CENTER, said, mono_medium(size), if dim { t.text_3 } else { t.text });
}

/// The track a node is bound to the meter of (`meter:<id>`).
fn bound_track(bind: Option<&str>) -> Option<&str> {
    bind.and_then(|b| b.strip_prefix("meter:"))
}

/// The loudest of late and whether the clip light is lit: the live values
/// when the node is bound to a track's meter, else those it was drawn with.
fn held(hold: f64, clipped: bool, bind: Option<&str>, live: &Value) -> (f32, bool) {
    match bound_track(bind) {
        Some(track) => (live["peaks"][track].as_f64().unwrap_or(0.0) as f32, live["clips"][track] == true),
        None => (hold as f32, clipped),
    }
}

/// Level meters, a column each, lit from the bottom in the meter colours
/// by where they reach, with the loudest of late a line and the clip light
/// on top: the live values when the meter is bound to a track's, else
/// those it was drawn with.
fn meter(painter: &Painter, rect: Rect, p: &MeterProps, bind: Option<&str>, live: &Value) {
    let t = th();
    let bound = bound_track(bind).and_then(|track| live["meters"][track].as_array());
    let mut levels: Vec<f32> = match bound {
        Some(l) => l.iter().map(|v| v.as_f64().unwrap_or(0.0) as f32).collect(),
        None => p.levels.iter().map(|v| *v as f32).collect(),
    };
    if levels.is_empty() {
        // Bound, before the first live values: both sides, silent.
        levels = vec![0.0; 2];
    }
    let n = levels.len().max(1) as f32;
    let gap = 1.0;
    let w = ((rect.width() - gap * (n - 1.0)) / n).max(1.0);
    let (hold, clipped) = held(p.hold, p.clipped, bind, live);
    // The clip light across the top, over a few points of its own.
    let light = Rect::from_min_size(rect.min, vec2(rect.width(), 4.0));
    painter.rect_filled(light, CornerRadius::same(1), if clipped { t.meter_clip } else { t.meter_well });
    let rect = Rect::from_min_max(pos2(rect.left(), light.bottom() + 2.0), rect.max);
    for (i, peak) in levels.iter().enumerate() {
        let column = Rect::from_min_size(pos2(rect.left() + i as f32 * (w + gap), rect.top()), vec2(w, rect.height()));
        painter.rect_filled(column, CornerRadius::ZERO, t.meter_well);
        let top = column.bottom() - column.height() * level(*peak);
        // In bands by level: to -18 dB, to -9, to -3, to 0.
        let mut from = column.bottom();
        for (db, colour) in [(-18.0f32, t.meter_low), (-9.0, t.meter_mid), (-3.0, t.meter_high), (0.0, t.meter_hot)] {
            let to = (column.bottom() - column.height() * (db + 60.0) / 60.0).max(top);
            if to < from {
                painter.rect_filled(Rect::from_min_max(pos2(column.left(), to), pos2(column.right(), from)), CornerRadius::ZERO, colour);
            }
            from = to;
            if to <= top {
                break;
            }
        }
        if level(hold) > 0.0 {
            let y = column.bottom() - column.height() * level(hold);
            painter.hline(column.x_range(), y, Stroke::new(1.0, if hold >= 1.0 { t.meter_clip } else { t.text_2 }));
        }
    }
}

/// Where a role node is in points, for a scene drawn from `at` with cells
/// `cell` big: its rectangle in units (left, top, right, bottom).
pub fn rect_of(units: [f64; 4], at: Pos2, cell: (f32, f32)) -> Rect {
    Rect::from_min_max(
        pos2(at.x + units[0] as f32 * cell.0, at.y + units[1] as f32 * cell.1),
        pos2(at.x + units[2] as f32 * cell.0, at.y + units[3] as f32 * cell.1),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_meter_reaches_as_far_as_the_terminals_does() {
        assert_eq!(level(1.0), 1.0);
        assert!((level(0.001) - 0.0).abs() < 1e-6, "-60 dB is the bottom");
        assert!((level(0.1) - 2.0 / 3.0).abs() < 1e-4, "-20 dB two thirds up");
    }

    #[test]
    fn each_role_the_window_says_it_paints_is_read_back_by_its_name() {
        for role in Role::ALL {
            assert_eq!(role.name().parse(), Ok(role));
        }
        assert_eq!("dial".parse::<Role>(), Err(UnknownRole), "left to the cells");
    }
}
