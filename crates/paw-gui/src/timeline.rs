//! The roles of the arrange view (runtime/lua/paw/roles/arrange.lua), as
//! the window paints them: a clip where it is between cells, with its notes
//! or its waveform, its fades, gain and warp markers; the ground of a row
//! of the timeline with the bars where they are; a level across a row with
//! the volume on it. The view lays them out in cells for both frontends;
//! the pointer over them goes back to the kernel as over any scene.
//!
//! What is inside a clip comes from the kernel by its key
//! (`paw.frontend.preview`, `paw.frontend.peaks`), once for each key: a
//! painter that has not got it asks for it (`wanted`), and the window
//! fetches it after the frame (`View::clip_pictures`).

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};

use egui::{Align2, Color32, CornerRadius, Painter, Rect, Shape, Stroke, StrokeKind, TextureHandle, Ui, pos2, vec2};
use paw_scene::props::{self, *};
use paw_scene::{Kind, Node};
use serde_json::{Value, json};

use crate::app::View;
use crate::model::{number, rows};
use crate::pictures::{notched, notes_picture, wave_picture, wave_points};
use crate::theme::{T_SMALL, alpha, mix, semi, th};
use crate::widgets;

/// What is inside a clip, asked for and not yet fetched.
struct Want {
    of: (i64, i64),
    key: String,
    midi: bool,
    length: f32,
    points: usize,
    notches: Vec<f32>,
}

/// The pictures inside clips by clip, with the key each was made for;
/// those asked for this frame, and the clips painted in it.
#[derive(Default)]
struct Pictures {
    made: HashMap<(i64, i64), (String, Option<TextureHandle>)>,
    wanted: Vec<Want>,
    painted: HashSet<(i64, i64)>,
    /// How many pictures were made: what was painted before one came is
    /// painted again.
    made_count: u64,
}

/// How many clips' pictures have been made so far.
pub fn pictures_made() -> u64 {
    PICTURES.with(|p| p.borrow().made_count)
}

thread_local! {
    static PICTURES: RefCell<Pictures> = RefCell::new(Pictures::default());
}

/// A clip: a bar along its top with its name, kept in view while its start
/// is scrolled away, over its body with its notes or its waveform; its
/// fades and their handles, the gain line while it is dragged, warp
/// markers and the notches of a loop; outlined when chosen or under the
/// pointer. One being dragged is a see-through copy where it will land.
pub fn clip(ui: &Ui, painter: &Painter, p: &ClipProps, rect: Rect, (cw, ch): (f32, f32)) {
    let t = th();
    let colour = p.color.and_then(crate::theme::hex).unwrap_or(t.select);
    // A pixel short of where the next clip starts, a pixel off the row's
    // top and bottom, never thinner than a mark.
    let shape = Rect::from_min_max(rect.min + vec2(0.0, 1.0), pos2(rect.right().max(rect.left() + 6.0) - 1.0, rect.bottom() - 2.0));
    let seen = painter.clip_rect();
    let under = ui.rect_contains_pointer(shape.intersect(seen));
    let font = semi(T_SMALL);
    if p.ghost {
        painter.rect(shape, CornerRadius::same(2), alpha(colour, 0.35), Stroke::new(1.0, Color32::WHITE), StrokeKind::Inside);
        let x = shape.left().max(seen.left()) + 5.0;
        let shown = widgets::elide(ui, p.name.unwrap_or(""), font.clone(), shape.right() - x - 3.0);
        painter.text(pos2(x, shape.top() + ch / 2.0), Align2::LEFT_CENTER, shown, font, Color32::WHITE);
        return;
    }
    if p.take.is_some() {
        return take(ui, painter, p, shape, colour, cw);
    }
    let (muted, current, midi) = (p.muted, p.current, p.midi);
    let face = if muted { t.panel } else { mix(colour, t.lane, if current { 0.40 } else { 0.26 }) };
    painter.rect_filled(shape, CornerRadius::same(2), face);
    // The bar along the top, a row high where the clip has a body under it.
    let bar_h = if shape.height() > ch * 1.5 { ch.min(16.0) } else { shape.height() };
    let bar = Rect::from_min_size(shape.min, vec2(shape.width(), bar_h));
    let bar_face = if muted { t.text_off } else if current { mix(colour, Color32::WHITE, 0.80) } else { colour };
    painter.rect_filled(bar, CornerRadius { nw: 2, ne: 2, sw: 0, se: 0 }, bar_face);
    let x = shape.left().max(seen.left()) + 5.0;
    let shown = widgets::elide(ui, p.label.unwrap_or(""), font.clone(), shape.right() - x - 3.0);
    painter.text(pos2(x, bar.center().y), Align2::LEFT_CENTER, shown, font, if muted { t.text_3 } else { t.on_hue });
    // Its notes or its waveform, white on clear, tinted.
    let body = Rect::from_min_max(pos2(shape.left(), bar.bottom() + 2.0), pos2(shape.right(), shape.bottom() - 2.0));
    let per = p.per as f32 * cw;
    let length = p.length as f32;
    if body.height() > 3.0 {
        let full = Rect::from_min_size(body.min, vec2((length * per).max(1.0), body.height()));
        if let Some(texture) = picture(p, midi, length, full.width()) {
            let ink = if muted { t.text_3 } else { mix(colour, Color32::WHITE, 0.8) };
            let shown = full.intersect(body).intersect(seen);
            if shown.width() > 0.0 {
                let (u0, u1) = ((shown.left() - full.left()) / full.width(), (shown.right() - full.left()) / full.width());
                painter.image(texture.id(), Rect::from_x_y_ranges(shown.x_range(), full.y_range()), Rect::from_min_max(pos2(u0, 0.0), pos2(u1, 1.0)), ink);
            }
        }
    }
    let at = |beat: f32| shape.left() + beat * per;
    if !midi {
        // The fades: the part above each line is faded away.
        let (fade_in, fade_out) = (at(p.fade_in as f32).clamp(shape.left(), shape.right()), (shape.right() - p.fade_out as f32 * per).clamp(shape.left(), shape.right()));
        let shade = alpha(t.surface, 0.55);
        if fade_in > shape.left() + 0.5 {
            painter.add(Shape::convex_polygon(vec![shape.left_top(), pos2(fade_in, shape.top()), shape.left_bottom()], shade, Stroke::new(1.0, t.text)));
        }
        if fade_out < shape.right() - 0.5 {
            painter.add(Shape::convex_polygon(vec![shape.right_top(), shape.right_bottom(), pos2(fade_out, shape.top())], shade, Stroke::new(1.0, t.text)));
        }
        // The gain line, while it is dragged: as high in the body as the
        // clip plays, 0 dB half way up, +6 dB at the top.
        if p.gain_line {
            let y = body.top() + (1.0 - (10f32.powf(p.gain as f32 / 20.0) / 2.0).clamp(0.0, 1.0)) * body.height();
            painter.hline(shape.x_range(), y, Stroke::new(1.0, t.select));
        }
        // The handles at the top corners, shown under the pointer.
        if under {
            let pointer = ui.input(|i| i.pointer.hover_pos());
            for x in [fade_in, fade_out] {
                let handle = Rect::from_center_size(pos2(x, shape.top() + 4.5), vec2(9.0, 9.0));
                let lit = pointer.is_some_and(|p| handle.contains(p));
                painter.rect_filled(handle, CornerRadius::same(2), if lit { t.select } else { alpha(t.text, 0.6) });
            }
        }
        // Warp markers: a line down the clip and a handle on its bar.
        for &beat in &p.warps {
            let x = at(beat as f32);
            painter.vline(x.round() + 0.5, shape.y_range(), Stroke::new(1.0, alpha(t.yellow, 0.8)));
            painter.add(Shape::convex_polygon(vec![pos2(x - 4.5, shape.top()), pos2(x + 4.5, shape.top()), pos2(x, shape.top() + 7.0)], t.yellow, Stroke::NONE));
        }
    }
    // Where each repeat of a looped clip begins.
    for &beat in &p.repeats {
        let x = at(beat as f32).round() + 0.5;
        if x > shape.left() + 1.0 && x < shape.right() - 1.0 {
            painter.add(Shape::dashed_line(&[pos2(x, body.top()), pos2(x, body.bottom())], Stroke::new(1.0, alpha(Color32::WHITE, 0.5)), 2.0, 2.0));
        }
    }
    // Chosen, under the cursor or under the pointer: an outline.
    let chosen = p.chosen;
    if current || chosen || under {
        let line = if current || chosen { Color32::WHITE } else { Color32::from_white_alpha(0x40) };
        painter.rect_stroke(shape, CornerRadius::same(2), Stroke::new(1.0, line), StrokeKind::Inside);
    }
    // An edge under the pointer, which a drag trims.
    if under && let Some(p) = ui.input(|i| i.pointer.hover_pos()) {
        let edge = cw * 0.9;
        if p.x - shape.left() < edge && shape.width() >= 3.0 * cw {
            painter.rect_filled(Rect::from_min_size(shape.min + vec2(1.0, 2.0), vec2(2.0, shape.height() - 4.0)), CornerRadius::same(1), Color32::from_white_alpha(0xa0));
        } else if shape.right() - p.x <= edge && shape.width() >= 2.0 * cw {
            painter.rect_filled(Rect::from_min_size(pos2(shape.right() - 3.0, shape.top() + 2.0), vec2(2.0, shape.height() - 4.0)), CornerRadius::same(1), Color32::from_white_alpha(0xa0));
        }
    }
}

/// A take of a clip in a take lane: its notes or its waveform over the
/// whole of it, lit in the track's colour where it is the take that plays,
/// faint where not; its name at its top left.
fn take(ui: &Ui, painter: &Painter, p: &ClipProps, shape: Rect, colour: Color32, cw: f32) {
    let t = th();
    let active = p.active;
    let seen = painter.clip_rect();
    painter.rect_filled(shape, CornerRadius::same(2), if active { mix(colour, t.lane, 0.38) } else { t.lane_alt });
    let length = p.length as f32;
    let full = Rect::from_min_size(shape.min, vec2((length * p.per as f32 * cw).max(1.0), shape.height()));
    if let Some(texture) = picture(p, p.midi, length, full.width()) {
        let ink = if active { mix(colour, Color32::WHITE, 0.8) } else { alpha(t.text_3, 0.7) };
        let shown = full.intersect(shape).intersect(seen);
        if shown.width() > 0.0 {
            let (u0, u1) = ((shown.left() - full.left()) / full.width(), (shown.right() - full.left()) / full.width());
            painter.image(texture.id(), Rect::from_x_y_ranges(shown.x_range(), full.y_range()), Rect::from_min_max(pos2(u0, 0.0), pos2(u1, 1.0)), ink);
        }
    }
    let x = shape.left().max(seen.left()) + 4.0;
    let font = if active { semi(T_SMALL) } else { crate::theme::sans(T_SMALL) };
    let shown = widgets::elide(ui, p.name.unwrap_or(""), font.clone(), shape.right() - x - 3.0);
    painter.text(pos2(x, shape.top() + 1.0), Align2::LEFT_TOP, shown, font, if active { t.text } else { t.text_3 });
    if active {
        painter.rect_stroke(shape, CornerRadius::same(2), Stroke::new(1.0, alpha(colour, 0.8)), StrokeKind::Inside);
    }
}

/// A track's header: the panel, lighter for the cursor's track, a stripe
/// of the track's colour down its left, a line under it, lit under the
/// pointer, where a drag makes the track taller or shorter.
pub fn trackhead(ui: &Ui, painter: &Painter, p: &TrackheadProps, rect: Rect) {
    let t = th();
    painter.rect_filled(rect, CornerRadius::ZERO, if p.selected { t.panel_sel } else { t.panel });
    let colour = p.color.and_then(crate::theme::hex).unwrap_or(t.text_3);
    painter.rect_filled(Rect::from_min_size(rect.min, vec2(4.0, rect.height())), CornerRadius::ZERO, colour);
    let edge = Rect::from_min_max(pos2(rect.left(), rect.bottom() - 5.0), rect.max);
    let lit = ui.rect_contains_pointer(edge);
    painter.hline(rect.x_range(), rect.bottom() - 0.5, Stroke::new(if lit { 2.0 } else { 1.0 }, if lit { alpha(t.select, 0.7) } else { t.divider }));
}

/// A take being recorded: a red box from where it began to the playhead,
/// as far as the punch-out, growing with the live values.
pub fn recording(painter: &Painter, p: &RecordingProps, bind: Option<&str>, live: &Value, rect: Rect, (cw, _): (f32, f32)) {
    let t = th();
    let start = p.start as f32;
    let at = match bind {
        Some("position") => live["position"].as_f64().map_or(p.at as f32, |v| v as f32),
        _ => p.at as f32,
    };
    let stop = p.to.map_or(at, |to| at.min(to as f32));
    if stop <= start {
        return;
    }
    let right = rect.left() + (stop - start) * p.per as f32 * cw;
    let shape = Rect::from_min_max(rect.min + vec2(0.0, 1.0), pos2(right.max(rect.left() + 2.0), rect.bottom() - 2.0));
    painter.rect(shape, CornerRadius::same(2), alpha(t.rec, 0.3), Stroke::new(1.0, t.rec), StrokeKind::Inside);
}

/// The picture inside a clip `width` points wide (or inside one of its
/// takes, in a take lane), by its key: the one made for it, else asked for
/// (and the last one made shown meanwhile).
/// A clip's picture is still shown, though its role was not painted in
/// this frame (its shapes were kept from an earlier one): it is kept.
pub fn keep_picture(node: &Node) {
    if let Kind::Role { props, .. } = &node.kind
        && let clip = props::parse::<ClipProps>(props)
        && let (Some(id), Some(_)) = (clip.id, clip.content)
    {
        PICTURES.with(|p| p.borrow_mut().painted.insert((id, clip.take.unwrap_or(0))));
    }
}

fn picture(props: &ClipProps, midi: bool, length: f32, width: f32) -> Option<TextureHandle> {
    let of = (props.id?, props.take.unwrap_or(0));
    let key = props.content?;
    let points = wave_points(width);
    let key = if midi { key.to_string() } else { format!("{key}@{points}") };
    PICTURES.with(|p| {
        let mut p = p.borrow_mut();
        p.painted.insert(of);
        let made = p.made.get(&of).cloned();
        if made.as_ref().is_some_and(|(k, _)| *k == key) {
            return made.and_then(|(_, t)| t);
        }
        if !p.wanted.iter().any(|w| w.of == of) {
            let notches = props.repeats.iter().map(|b| *b as f32 / length.max(1e-6)).collect();
            p.wanted.push(Want { of, key, midi, length, points, notches });
        }
        made.and_then(|(_, t)| t)
    })
}

/// The ground of a row of the timeline: a lane, lighter every other row
/// and tinted for the cursor's track, a take lane, an automation lane;
/// the loop shaded over it; a line on each bar, and on each beat where
/// the view draws them, where it is.
pub fn ground(painter: &Painter, p: &BeatsProps, rect: Rect, (cw, _): (f32, f32)) {
    let t = th();
    let face = match p.tone {
        Some("take") => alpha(t.panel, 0.55),
        Some("auto") => alpha(t.panel, 0.7),
        _ if p.selected => Color32::from_rgb(0x24, 0x26, 0x2b),
        _ if p.index % 2 == 0 => t.lane_alt,
        _ => t.lane,
    };
    painter.rect_filled(rect, CornerRadius::ZERO, face);
    let (from, per) = (p.from as f32, p.per as f32 * cw);
    let x = |beat: f32| rect.left() + (beat - from) * per;
    if let Some((a, b)) = p.looped {
        let (a, b) = (x(a as f32).max(rect.left()), x(b as f32).min(rect.right()));
        if b > a {
            painter.rect_filled(Rect::from_x_y_ranges(a..=b, rect.y_range()), CornerRadius::ZERO, Color32::from_rgba_unmultiplied(0xfe, 0xc1, 0x3a, 0x10));
        }
    }
    for &(beat, bar) in &p.lines {
        if !bar && !p.beats {
            continue;
        }
        let at = x(beat as f32).round() + 0.5;
        painter.vline(at, rect.y_range(), Stroke::new(1.0, if bar { t.line_bar } else { t.line_beat }));
    }
    painter.hline(rect.x_range(), rect.bottom() - 0.5, Stroke::new(1.0, t.divider));
}

/// A curve over a stretch of time: a line through its values, one each
/// half column, broken where there is none, in its track's colour, grey
/// when it is off; a dot on each of its points.
pub fn curve(painter: &Painter, p: &CurveProps, rect: Rect, (cw, _): (f32, f32)) {
    let t = th();
    let colour = if p.enabled == Some(false) {
        t.text_3
    } else {
        p.color.and_then(crate::theme::hex).map_or(t.yellow, |c| mix(c, Color32::WHITE, 0.7))
    };
    let y = |v: f32| rect.top() + 2.0 + (1.0 - v.clamp(0.0, 1.0)) * (rect.height() - 4.0);
    let stroke = Stroke::new(1.5, colour);
    let mut line = Vec::new();
    for (i, v) in p.values.iter().enumerate() {
        match v {
            Some(v) => line.push(pos2(rect.left() + (i as f32 + 0.5) / 2.0 * cw, y(*v as f32))),
            None => {
                if line.len() > 1 {
                    painter.add(Shape::line(std::mem::take(&mut line), stroke));
                }
                line.clear();
            }
        }
    }
    if line.len() > 1 {
        painter.add(Shape::line(line, stroke));
    }
    let (from, per) = (p.from as f32, p.per as f32 * cw);
    for &(beat, value) in &p.points {
        let x = rect.left() + (beat as f32 - from) * per;
        if rect.x_range().contains(x) {
            painter.circle_filled(pos2(x, y(value as f32)), 3.0, t.text);
        }
    }
}

/// A level across a row: a well lit from the left in the meter colours by
/// how far it reaches on the fader's scale, both sides a half each, the
/// loudest of late a line; with `at`, a fader's cap where the volume stands.
pub fn hmeter(painter: &Painter, p: &HmeterProps, bind: Option<&str>, live: &Value, rect: Rect, under: bool) {
    let t = th();
    let track = bind.and_then(|b| b.strip_prefix("meter:"));
    let levels: Vec<f32> = match track.map(|id| &live["meters"][id]).filter(|v| v.is_array()) {
        Some(bound) => rows(bound).iter().map(number).collect(),
        None => p.levels.iter().map(|v| *v as f32).collect(),
    };
    let hold = track.and_then(|id| live["peaks"][id].as_f64()).map_or(p.hold as f32, |v| v as f32);
    let clipped = track.map_or(p.clipped, |id| live["clips"][id] == true);
    // The clip light at its right end, lit once a level reached full scale.
    let light = Rect::from_min_max(pos2(rect.right() - 5.0, rect.center().y - 4.0), pos2(rect.right() - 1.0, rect.center().y + 4.0));
    painter.rect_filled(light, CornerRadius::same(1), if clipped { t.meter_clip } else { t.meter_well });
    let well = Rect::from_min_max(pos2(rect.left() + 1.0, rect.center().y - (rect.height() * 0.3).clamp(3.0, 5.5)), pos2(light.left() - 2.0, rect.center().y + (rect.height() * 0.3).clamp(3.0, 5.5)));
    painter.rect(well, CornerRadius::same(2), t.meter_well, Stroke::new(1.0, t.divider), StrokeKind::Outside);
    // On the fader's scale, -60 to +6 dB, so that a level stands where the
    // fader's cap would stand for it.
    let reach = |peak: f32| ((20.0 * peak.max(1e-6).log10() + 60.0) / 66.0).clamp(0.0, 1.0);
    let bands = |part: Rect, peak: f32| {
        let end = part.left() + part.width() * reach(peak);
        let mut from = part.left();
        for (db, colour) in [(-18.0f32, t.meter_low), (-9.0, t.meter_mid), (-3.0, t.meter_high), (0.0, t.meter_hot), (6.0, t.meter_clip)] {
            let to = (part.left() + part.width() * (db + 60.0) / 66.0).min(end);
            if to > from {
                painter.rect_filled(Rect::from_x_y_ranges(from..=to, part.y_range()), CornerRadius::ZERO, colour);
            }
            from = to;
            if to >= end {
                break;
            }
        }
    };
    // Both sides, a thin bar each.
    let (left, right) = (levels.first().copied().unwrap_or(0.0), levels.get(1).copied().unwrap_or(0.0));
    let half = well.height() / 2.0;
    bands(Rect::from_min_size(well.min, vec2(well.width(), half - 0.5)), left);
    bands(Rect::from_min_size(well.min + vec2(0.0, half + 0.5), vec2(well.width(), half - 0.5)), right);
    if hold > 1e-5 {
        let x = well.left() + well.width() * reach(hold);
        painter.vline(x, well.y_range(), Stroke::new(1.0, if hold >= 1.0 { t.meter_clip } else { t.text_2 }));
    }
    if let Some(at) = p.at {
        let x = well.left() + well.width() * (at as f32).clamp(0.0, 1.0);
        let cap = Rect::from_center_size(pos2(x, rect.center().y), vec2(5.0, (rect.height() - 2.0).max(6.0)));
        painter.rect_filled(cap, CornerRadius::same(1), if under { t.bright } else { t.thumb });
    }
}

impl View {
    /// Fetch what clips' painters asked for in the frame, and draw them
    /// again with it; let go of the pictures of clips not painted in it.
    pub fn clip_pictures(&mut self, ctx: &egui::Context) {
        let wanted = PICTURES.with(|p| {
            let mut p = p.borrow_mut();
            let painted = std::mem::take(&mut p.painted);
            p.made.retain(|id, _| painted.contains(id));
            std::mem::take(&mut p.wanted)
        });
        if wanted.is_empty() {
            return;
        }
        for w in wanted {
            let (id, take) = w.of;
            let call = match (take, w.midi) {
                (0, true) => json!(["return paw.frontend.preview(...)", id]),
                (0, false) => json!(["return paw.frontend.peaks(...)", id, w.points]),
                _ => json!(["return paw.frontend.take_preview(...)", id, take, w.points]),
            };
            let flat: Vec<f32> = self.k.borrow_mut().call("eval", call).map(|v| rows(&v).iter().map(number).collect()).unwrap_or_default();
            let made = if w.midi { notes_picture(&flat, w.length) } else { wave_picture(&flat) };
            let texture = made.map(|image| ctx.load_texture(format!("clip-{id}-{take}"), notched(image, &w.notches), egui::TextureOptions::NEAREST));
            PICTURES.with(|p| {
                let mut p = p.borrow_mut();
                p.made.insert(w.of, (w.key, texture));
                p.made_count += 1;
            });
        }
        self.repaint = true;
        ctx.request_repaint();
    }
}
