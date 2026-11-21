//! The main area as the kernel's tabs and windows lay it out
//! (`runtime/lua/paw/panes.tl`): where each view the window draws itself
//! goes, the scenes of the views the kernel draws (crate::scene), the
//! borders, the tabs and the pane with the keyboard. Gestures go back to
//! `paw.panes`.

use egui::{CornerRadius, Id, Pos2, Rect, Sense, Stroke, StrokeKind, Ui, pos2, vec2};
use serde_json::{Value, json};

use crate::app::View;
use crate::icons;
use crate::model::{number, rows, text};
use crate::theme::{T_SMALL, alpha, semi, th};
use crate::widgets::{self, Look};

/// The height of a kernel's pane's title along its top, and the inset of
/// its picture from the pane's sides and bottom.
pub const HEADING: f32 = 24.0;
pub const PAD: f32 = 6.0;
/// The row of tabs along the top, when there is more than one.
const TABS: f32 = 28.0;

#[derive(Default)]
pub struct Panes {
    /// The size of the main area the kernel was last told.
    told: (f32, f32),
    /// A border being dragged, by its place.
    border: Option<usize>,
}

fn pane_rect(p: &Value) -> Rect {
    Rect::from_min_size(pos2(number(&p["x"]), number(&p["y"])), vec2(number(&p["w"]), number(&p["h"])))
}

/// A pointer event as `paw.panes.pointer` and `paw.canvas.pointer` take it.
pub fn pointer_event(kind: &str, at: Pos2, button: &str, m: egui::Modifiers) -> Value {
    json!({ "kind": kind, "x": at.x, "y": at.y, "button": button, "ctrl": m.ctrl, "shift": m.shift, "alt": m.alt })
}

/// The pointer's events over `rect` this frame, in its own coordinates, as
/// a view that paints takes them: down, up, move (a button held), double,
/// hover, wheel.
pub fn pointer_events(ui: &Ui, rect: Rect, id: Id) -> Vec<Value> {
    let response = ui.interact(rect, id, Sense::click_and_drag());
    let mut out = Vec::new();
    // Held from a press in an earlier frame, or in this one: on a loaded
    // machine a press, the moves and the release can all come in one frame.
    let mut held = ui.data(|d| d.get_temp::<bool>(id)).unwrap_or(false);
    // A press here whose pointer has left by the end of the frame: where
    // the press was, on this window and not on a menu above it.
    let visible = ui.clip_rect().intersect(rect);
    let over = |p: Pos2| visible.contains(p) && ui.ctx().layer_id_at(p).is_none_or(|l| l == ui.layer_id());
    // Out of `input`, which holds the lock of the context that `over` asks.
    let (events, m, hover) = ui.input(|i| (i.events.clone(), i.modifiers, i.pointer.hover_pos()));
    let at = |p: Pos2| (p - rect.min).to_pos2();
    for event in &events {
        match event {
            egui::Event::PointerButton { pos, button, pressed, modifiers } => {
                let name = match button {
                    egui::PointerButton::Secondary => "right",
                    egui::PointerButton::Middle => "middle",
                    _ => "left",
                };
                if *pressed && (response.hovered() || (!response.contains_pointer() && over(*pos))) {
                    out.push(pointer_event("down", at(*pos), name, *modifiers));
                    held = true;
                } else if !*pressed && (held || response.hovered()) {
                    out.push(pointer_event("up", at(*pos), name, *modifiers));
                    held = false;
                }
            }
            egui::Event::PointerMoved(pos) if held => out.push(pointer_event("move", at(*pos), "left", m)),
            egui::Event::PointerMoved(pos) if response.hovered() => out.push(pointer_event("hover", at(*pos), "left", m)),
            egui::Event::MouseWheel { delta, modifiers, .. } if response.hovered() => {
                if let Some(pos) = hover {
                    let p = at(pos);
                    out.push(json!({ "kind": "wheel", "x": p.x, "y": p.y, "dx": delta.x, "dy": delta.y, "ctrl": modifiers.ctrl, "shift": modifiers.shift }));
                }
            }
            _ => {}
        }
    }
    if response.double_clicked()
        && let Some(pos) = ui.input(|i| i.pointer.interact_pos())
    {
        out.push(pointer_event("double", (pos - rect.min).to_pos2(), "left", ui.input(|i| i.modifiers)));
    }
    let pressed = response.is_pointer_button_down_on() || (held && ui.input(|i| i.pointer.any_down()));
    ui.data_mut(|d| d.insert_temp(id, pressed));
    out
}

impl View {
    /// Tell the kernel the main area's size when it has changed; and a press
    /// anywhere in a pane gives it the keyboard.
    pub fn pane_area(&mut self, ui: &Ui, area: Rect) {
        let size = (area.width().round(), area.height().round());
        if size != self.panes.told && size.0 > 0.0 && size.1 > 0.0 {
            self.panes.told = size;
            self.eval("paw.panes.area(...)", json!([size.0, size.1]));
        }
        if self.menu.is_some() || self.text_focus || self.dialogs.open() {
            return;
        }
        let press = [egui::PointerButton::Primary, egui::PointerButton::Secondary, egui::PointerButton::Middle];
        let Some(pos) = press.into_iter().find_map(|b| crate::widgets::pressed_at(ui, b)) else { return };
        if !area.contains(pos) {
            return;
        }
        let at = pos - area.min.to_vec2();
        for pane in rows(&self.s.modal["panes"]["panes"]) {
            if pane_rect(pane).contains(at) && pane["focused"] != true {
                self.eval("paw.panes.focus(...)", json!([pane["win"]]));
                break;
            }
        }
    }

    /// The panes the kernel draws, the borders, the ring round the pane
    /// with the keyboard, and the tabs.
    pub fn draw_kernel_panes(&mut self, ui: &mut Ui, area: Rect, state: &Value) {
        let t = th();
        let all = rows(&state["panes"]);
        let (_, cell_h) = self.scenes.cell();
        for pane in all {
            let kind = pane["kind"].as_str().unwrap_or("");
            if kind == "native" {
                continue;
            }
            let win = pane["win"].as_i64().unwrap_or(0);
            let rect = pane_rect(pane).translate(area.min.to_vec2());
            let focused = pane["focused"] == true;
            ui.painter().rect_filled(rect, CornerRadius::ZERO, t.surface);
            // A view whose title row has its own buttons (the piano roll) is
            // shown whole, edge to edge, under no title of the window's.
            if pane["titled"] == true {
                self.scene(ui, &win.to_string(), rect, rect);
                continue;
            }
            // A view in cells draws a title row of its own, which the
            // pane's title covers.
            let under = if kind == "paint" { 0.0 } else { cell_h };
            let picture = Rect::from_min_max(pos2(rect.left() + PAD, rect.top() + HEADING - under), pos2(rect.right() - PAD, rect.bottom() - PAD));
            self.scene(ui, &win.to_string(), picture, rect);
            // The title over the top, over the picture's own title row.
            let title = Rect::from_min_size(rect.min, vec2(rect.width(), HEADING));
            ui.painter().rect_filled(title, CornerRadius::ZERO, if focused { t.panel_sel } else { t.panel });
            widgets::text_in(
                ui,
                pos2(title.left() + 10.0, title.center().y),
                &text(&pane["title"]),
                semi(T_SMALL),
                if focused { t.text } else { t.text_2 },
                title.width() - 80.0,
            );
            let close = Rect::from_min_size(pos2(title.right() - 24.0, title.top() + 2.0), vec2(20.0, 20.0));
            let out = close.translate(vec2(-22.0, 0.0));
            let response = widgets::button(ui, out, Id::unique(("pane-out", win)), Some(icons::ARROW_SQUARE_OUT), "", Look::quiet());
            widgets::hint_on(&response, "open in a window of its own (Ctrl-w f)");
            if response.clicked() {
                self.command(&format!("view.window {}", text(&pane["view"])));
            }
            let response = widgets::button(ui, close, Id::unique(("pane-close", win)), Some(icons::X), "", Look::quiet());
            widgets::hint_on(&response, "close the window (:q)");
            if response.clicked() {
                self.eval("paw.panes.close(...)", json!([win]));
            }
        }
        // The borders between panes, dragged to share the room.
        for (i, border) in rows(&state["borders"]).iter().enumerate() {
            let across = border["dir"] == "h";
            let (x, y, length) = (number(&border["x"]), number(&border["y"]), number(&border["length"]));
            let grip = if across {
                Rect::from_min_size(pos2(area.left() + x - 3.0, area.top() + y), vec2(6.0, length))
            } else {
                Rect::from_min_size(pos2(area.left() + x, area.top() + y - 3.0), vec2(length, 6.0))
            };
            let response = ui.interact(grip, Id::unique(("pane-border", i)), Sense::drag());
            let lit = response.hovered() || response.dragged();
            let colour = if lit { alpha(t.select, 0.7) } else { t.divider };
            if across {
                ui.painter().vline(grip.center().x, grip.y_range(), Stroke::new(1.0, colour));
            } else {
                ui.painter().hline(grip.x_range(), grip.center().y, Stroke::new(1.0, colour));
            }
            if lit {
                ui.ctx().set_cursor_icon(if across { egui::CursorIcon::ResizeHorizontal } else { egui::CursorIcon::ResizeVertical });
                widgets::hint("drag to share the room between the windows");
            }
            if response.dragged()
                && let Some(pos) = response.interact_pointer_pos()
            {
                let at = pos - area.min.to_vec2();
                self.panes.border = Some(i);
                self.eval("paw.panes.border(...)", json!([i + 1, at.x, at.y]));
            }
        }
        // The ring round the pane with the keyboard, when there are several.
        if all.len() > 1
            && let Some(pane) = all.iter().find(|p| p["focused"] == true)
        {
            let rect = pane_rect(pane).translate(area.min.to_vec2());
            ui.painter().rect_stroke(rect.shrink(1.0), CornerRadius::ZERO, Stroke::new(2.0, alpha(t.select, 0.85)), StrokeKind::Middle);
        }
        // The tabs, along the top when there is more than one (or always,
        // as the configuration says): each with its close button, and a
        // button for a new tab after the last.
        let tabs = rows(&state["tabs"]);
        if number(&state["top"]) > 0.0 {
            self.tab_row(ui, area, state, &tabs);
        }
    }

    /// The row of tabs. A click on a tab goes to it, a middle click or its
    /// close button closes it, a drag moves it among the others (as
    /// `:tabmove`), and `+` opens a new tab on the start page (`:tabnew`).
    /// Every tab is as wide, so that a drop lands on a slot.
    fn tab_row(&mut self, ui: &mut Ui, area: Rect, state: &Value, tabs: &[Value]) {
        let t = th();
        let bar = Rect::from_min_size(area.min, vec2(area.width(), TABS));
        ui.painter().rect_filled(bar, CornerRadius::ZERO, t.panel);
        ui.painter().hline(bar.x_range(), bar.bottom() - 0.5, Stroke::new(1.0, t.divider));
        let current = state["tab"].as_i64().unwrap_or(1) as usize;
        let slot = |x: f32| (((x - bar.left() - TAB_LEFT) / (TAB_W + TAB_GAP)).floor().max(0.0) as usize + 1).min(tabs.len());
        for (i, tab) in tabs.iter().enumerate() {
            let on = i + 1 == current;
            let label = format!("{}  {}", i + 1, text(&tab["title"]));
            let font = if on { semi(T_SMALL) } else { crate::theme::sans(T_SMALL) };
            let rect = tab_rect(bar, i);
            let response = ui.interact(rect, Id::unique(("tab", i)), Sense::click_and_drag());
            let face = if on { t.surface } else if response.hovered() { egui::Color32::from_white_alpha(0x12) } else { egui::Color32::TRANSPARENT };
            ui.painter().rect_filled(rect, CornerRadius::same(4), face);
            if on {
                ui.painter().rect_filled(Rect::from_min_size(rect.min, vec2(rect.width(), 2.0)), CornerRadius::ZERO, t.select);
            }
            widgets::text_in(ui, pos2(rect.left() + 10.0, rect.center().y), &label, font, if on { t.text } else { t.text_2 }, TAB_W - 40.0);
            let close = Rect::from_center_size(pos2(rect.right() - 13.0, rect.center().y), vec2(18.0, 18.0));
            let shut = widgets::button(ui, close, Id::unique(("tab-close", i)), Some(icons::X), "", Look::quiet());
            widgets::hint_on(&shut, "close the tab (:tabclose)");
            widgets::hint_on(&response, "drag to move the tab (:tabmove); a middle click closes it");
            // Where a drag would put the tab: a mark at the slot.
            if response.dragged()
                && let Some(pos) = response.interact_pointer_pos()
            {
                let to = slot(pos.x);
                if to != i + 1 {
                    let edge = tab_rect(bar, to - 1);
                    let x = if to > i + 1 { edge.right() + TAB_GAP / 2.0 } else { edge.left() - TAB_GAP / 2.0 };
                    ui.painter().vline(x, edge.y_range(), Stroke::new(2.0, t.select));
                }
            }
            if shut.clicked() || response.middle_clicked() {
                self.eval("paw.panes.tab_close(...)", json!([i + 1]));
            } else if response.drag_stopped() {
                let to = response.interact_pointer_pos().map(|p| slot(p.x)).unwrap_or(i + 1);
                if to != i + 1 {
                    self.eval("paw.panes.tab_move(...)", json!([i + 1, to]));
                }
            } else if response.clicked() {
                self.eval("paw.panes.tab(...)", json!([i + 1]));
            }
        }
        let plus = Rect::from_min_size(pos2(tab_rect(bar, tabs.len()).left(), bar.top() + 4.0), vec2(22.0, 22.0));
        let response = widgets::button(ui, plus, Id::unique("tab-new"), Some(icons::PH_PLUS), "", Look::quiet());
        widgets::hint_on(&response, "a new tab (:tabnew)");
        if response.clicked() {
            self.eval("paw.panes.tab_new()", json!([]));
        }
    }
}

/// Every tab is this wide, with this gap between, from this far in.
const TAB_W: f32 = 150.0;
const TAB_GAP: f32 = 2.0;
const TAB_LEFT: f32 = 6.0;

/// Where tab `i` (from 0) is in the row of tabs.
fn tab_rect(bar: Rect, i: usize) -> Rect {
    Rect::from_min_size(pos2(bar.left() + TAB_LEFT + i as f32 * (TAB_W + TAB_GAP), bar.top() + 3.0), vec2(TAB_W, TABS - 3.0))
}
