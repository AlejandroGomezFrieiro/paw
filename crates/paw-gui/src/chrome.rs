//! What runs round the main area: the transport bar along the top, the
//! status line along the bottom, and what is drawn over the window for the
//! keyboard's sake (what a command line could become, the keys that can
//! follow, a page the kernel draws).

use egui::{Align2, Color32, CornerRadius, Id, Order, Pos2, Rect, Sense, Stroke, StrokeKind, Ui, pos2, vec2};
use serde_json::json;

use crate::app::View;
use crate::icons;
use crate::live::Part;
use crate::model::{flag, int, number, rows, text};
use crate::theme::{T_BASE, T_CLOCK, T_MICRO, T_SMALL, T_TITLE, alpha, mix, mode_colour, mono, mono_medium, sans, semi, th};
use crate::widgets::{self, Look};

impl View {
    /// The transport bar.
    pub fn transport(&mut self, ui: &mut Ui, bar: Rect) {
        let t = th();
        ui.painter().rect_filled(bar, CornerRadius::ZERO, t.panel);
        let (top, h) = (bar.top() + 6.0, 28.0);
        let row = |x: f32, w: f32| Rect::from_min_size(pos2(x, top), vec2(w, h));
        let mut x = bar.left() + 12.0;
        // The project, and whether it has changes to save.
        let name = format!("{}  ▾", text(&self.s.project["name"]));
        let name_w = widgets::text_width(ui, &name, semi(T_TITLE)).min(180.0 - 12.0);
        let modified = flag(&self.s.project["modified"]);
        let project = row(x, name_w + 12.0);
        widgets::text_in(ui, pos2(x, project.center().y), &name, semi(T_TITLE), t.text, name_w + 1.0);
        if modified {
            ui.painter().circle_filled(pos2(x + name_w + 9.0, project.center().y), 3.0, t.play);
        }
        let response = ui.interact(project, Id::unique("file-menu"), Sense::click());
        widgets::hint_on(&response, "project: click for the file menu: new, open, save, import, render, quit");
        if response.clicked() {
            self.open_menu("file", json!([]), project.left_bottom() + vec2(0.0, 4.0));
        }
        x = project.right() + 8.0 + 4.0;
        // The transport's buttons, together.
        let counting = int(&self.s.tick["counting"]);
        let armed = flag(&self.s.tick["armed"]);
        let looping = flag(&self.s.project["loop_enabled"]);
        let metronome = flag(&self.s.project["metronome"]);
        let buttons: [(&str, icons::Icon, Look); 6] = [
            ("start", icons::SKIP_BACK_FILL, Look::quiet()),
            ("stop", icons::STOP_FILL, Look::quiet()),
            ("play", if self.s.playing { icons::PAUSE_FILL } else { icons::PLAY_FILL }, Look::quiet().on(self.s.playing).lit(t.play_on)),
            (
                "record",
                icons::RECORD_FILL,
                Look {
                    // While counting in it blinks with the beats.
                    on: if counting > 0 { counting % 2 == 0 } else { self.s.recording || armed },
                    lit: t.rec,
                    idle_ink: Some(mix(t.rec, t.text_3, 0.6)),
                    ..Look::quiet()
                },
            ),
            ("loop", icons::REPEAT, Look::quiet().on(looping)),
            ("click", icons::METRONOME, Look::quiet().on(metronome)),
        ];
        for (name, shape, look) in buttons {
            let response = widgets::button(ui, row(x, h), Id::unique(("transport", name)), Some(shape), "", look);
            widgets::name(&response, name);
            if name == "record" {
                widgets::hint_on(&response, "record: starts a take on the armed tracks (R on a track), or on the selected one if none is armed · again to stop");
            }
            if response.clicked() {
                match name {
                    "start" => self.acts_seek(0.0),
                    "stop" => self.command("transport.stop"),
                    "play" => self.command("transport.toggle"),
                    "record" => self.pass("record", json!([])),
                    "loop" => self.command("transport.loop"),
                    _ => self.command("transport.metronome"),
                }
            }
            x += h + 2.0;
        }
        x += 6.0;
        // Where the playhead is: bars and beats, then minutes and seconds.
        let clock = row(x, 168.0);
        ui.painter().rect_filled(clock, CornerRadius::same(4), t.well);
        let part = self.live.begin(ui.painter(), Part::Clock { rect: clock });
        self.clock(ui.painter(), clock);
        self.live.end(ui.painter(), part);
        x = clock.right() + 8.0;
        // Tempo: the wheel changes it, or a drag up and down; a double click types it.
        let tempo = row(x, 64.0);
        let response = ui.interact(tempo, Id::unique("tempo"), Sense::click_and_drag());
        widgets::name(&response, "tempo");
        ui.painter().rect_filled(tempo, CornerRadius::same(4), if response.hovered() { t.control_press } else { t.well });
        let bpm = self.s.tick["tempo"].as_f64().or(self.s.project["tempo"].as_f64()).unwrap_or(120.0);
        ui.painter().text(pos2(tempo.right() - 6.0 - 22.0, tempo.center().y), Align2::RIGHT_CENTER, format!("{bpm}"), mono_medium(T_BASE), t.text);
        ui.painter().text(pos2(tempo.right() - 6.0, tempo.center().y), Align2::RIGHT_CENTER, "BPM", semi(T_MICRO), t.text_3);
        widgets::hint_on(&response, "tempo: wheel or drag up and down to change it · double click to type it");
        if response.hovered() {
            ui.ctx().set_cursor_icon(egui::CursorIcon::ResizeVertical);
        }
        if response.double_clicked() {
            self.feed(":tempo ");
        } else if response.dragged() {
            let id = Id::unique("tempo-drag");
            let moved = ui.data(|d| d.get_temp::<f32>(id)).unwrap_or(0.0) + response.drag_delta().y;
            if moved.abs() >= 6.0 {
                self.command(if moved < 0.0 { "tempo by=1" } else { "tempo by=-1" });
                ui.data_mut(|d| d.insert_temp(id, 0.0f32));
            } else {
                ui.data_mut(|d| d.insert_temp(id, moved));
            }
        }
        if let Some(step) = widgets::wheel_step(ui, &response) {
            self.command(if step > 0.0 { "tempo by=1" } else { "tempo by=-1" });
        }
        x = tempo.right() + 8.0;
        let signature = row(x, 48.0);
        ui.painter().rect_filled(signature, CornerRadius::same(4), t.well);
        let sig = self.s.tick["signature"].as_str().map(String::from).unwrap_or_else(|| text(&self.s.project["signature"]));
        ui.painter().text(signature.center(), Align2::CENTER_CENTER, sig, mono_medium(T_BASE), t.text);
        x = signature.right() + 16.0;
        for (name, shape) in [("undo", icons::ARROW_COUNTER_CLOCKWISE), ("redo", icons::ARROW_CLOCKWISE)] {
            if widgets::button(ui, row(x, h), Id::unique(("transport", name)), Some(shape), "", Look::quiet()).clicked() {
                self.command(name);
            }
            x += h + 2.0;
        }
        x += 14.0;
        // A new track: at once, or from a list when extensions have kinds
        // of track of their own to offer.
        let w = widgets::button_width(ui, "Track", true, h);
        let add = row(x, w);
        if widgets::button(ui, add, Id::unique("add-track"), Some(icons::PH_PLUS), "Track", Look::default()).clicked() {
            self.open_menu("add_track", json!([]), add.left_bottom() + vec2(0.0, 2.0));
        }
        x = add.right() + 8.0;
        // Which views show: one segmented switch.
        let roll_open = rows(&self.s.modal["panes"]["panes"]).iter().any(|p| p["view"] == "pianoroll");
        let lanes_open = self.s.track(self.s.selected).is_some_and(|t| !t.lane_rows.is_empty());
        let views: [(&str, icons::Icon, bool, &str); 4] = [
            ("Mixer", icons::FADERS, flag(&self.s.modal["mixer"]), ""),
            ("Automation", icons::CHART_LINE, lanes_open, "automation: the selected track's lanes as rows under it, to draw on, or hidden"),
            ("Piano roll", icons::PIANO_KEYS, roll_open, "piano roll: opens the notes of the clip at the cursor, or closes them"),
            ("More", icons::CARET_DOWN, false, "more views: the undo tree, sections, an extension's panel… each in a pane of the window"),
        ];
        let widths: Vec<f32> = views.iter().map(|v| widgets::button_width(ui, v.0, true, 24.0)).collect();
        let segment = Rect::from_min_size(pos2(x, top), vec2(widths.iter().sum::<f32>() + 2.0 * views.len() as f32 + 2.0, h));
        ui.painter().rect_filled(segment, CornerRadius::same(4), t.well);
        let mut vx = segment.left() + 2.0;
        for ((label, shape, on, tip), w) in views.into_iter().zip(widths) {
            let rect = Rect::from_min_size(pos2(vx, top + 2.0), vec2(w, 24.0));
            let response = widgets::button(ui, rect, Id::unique(("view", label)), Some(shape), label, Look::quiet().on(on));
            if !tip.is_empty() {
                widgets::hint_on(&response, tip);
            }
            if response.clicked() {
                match label {
                    "Mixer" => self.command("view.toggle mixer"),
                    "Automation" => self.command("lane.rows"),
                    "Piano roll" => self.command(if roll_open { "view.toggle pianoroll" } else { "clip.edit" }),
                    _ => self.open_menu("views", json!([]), rect.left_bottom() + vec2(0.0, 2.0)),
                }
            }
            vx += w + 2.0;
        }
        // How hard the engine is working; a click chooses the devices.
        let engine_w = 220.0f32.min((bar.right() - 12.0 - segment.right() - 16.0).max(48.0));
        let engine = Rect::from_min_size(pos2(bar.right() - 12.0 - engine_w, top), vec2(engine_w, h));
        let response = ui.interact(engine, Id::unique("engine"), Sense::click());
        widgets::name(&response, "engine");
        if response.hovered() {
            ui.painter().rect_filled(engine, CornerRadius::same(4), Color32::from_white_alpha(0x12));
        }
        widgets::hint_on(&response, "audio: click to choose the output and input devices and the block size");
        if response.clicked() {
            let opts = json!({ "remote": !self.ours, "listening": self.listening });
            self.open_menu("engine", json!([opts]), engine.left_bottom());
        }
        let meter = Rect::from_min_size(pos2(engine.right() - 6.0 - 40.0, engine.center().y - 2.0), vec2(40.0, 4.0));
        let part = self.live.begin(ui.painter(), Part::Load { rect: meter });
        self.load(ui.painter(), meter);
        self.live.end(ui.painter(), part);
        let (said, colour) = match &self.note {
            Some((message, error, _)) => (message.clone(), if *error { t.error } else { t.text_3 }),
            None => (text(&self.s.project["engine"]), t.text_3),
        };
        let room = engine.width() - 6.0 - 40.0 - 8.0;
        let shown = widgets::elide(ui, &said, sans(T_SMALL), room);
        ui.painter().text(pos2(meter.left() - 8.0, engine.center().y), Align2::RIGHT_CENTER, shown, sans(T_SMALL), colour);
    }

    /// The clock's words: where the playhead is, in bars and beats and in
    /// minutes and seconds; while counting in, the beats left.
    pub fn clock(&self, painter: &egui::Painter, clock: Rect) {
        let t = th();
        let counting = int(&self.s.tick["counting"]);
        let (time, colour) = if counting > 0 { (format!("count {counting}"), t.rec) } else { (text(&self.s.tick["time"]), t.text) };
        painter.text(pos2(clock.left() + 10.0, clock.center().y), Align2::LEFT_CENTER, time, mono_medium(T_CLOCK), colour);
        painter.text(pos2(clock.right() - 10.0, clock.center().y), Align2::RIGHT_CENTER, text(&self.s.tick["clock"]), mono(T_SMALL), t.text_3);
    }

    /// How hard the engine works, as a bar filled from the left.
    pub fn load(&self, painter: &egui::Painter, meter: Rect) {
        let t = th();
        let cpu = number(&self.s.tick["cpu"]).clamp(0.0, 1.0);
        painter.rect_filled(meter, CornerRadius::same(2), t.well);
        let load = if cpu > 0.9 { t.error } else if cpu > 0.7 { t.warn } else { t.text_3 };
        painter.rect_filled(Rect::from_min_size(meter.min, vec2(40.0 * cpu, 4.0)), CornerRadius::same(2), load);
    }

    fn acts_seek(&self, beat: f32) {
        self.k_call("transport_seek", json!([beat.max(0.0)]));
    }

    /// A call of the control protocol, at the end of the frame.
    pub fn k_call(&self, method: &str, params: serde_json::Value) {
        self.eval(&format!("return paw.api.{method}(...)"), params);
    }

    /// The status line: the mode, then the prompt or the last message, or
    /// else what the pointer does where it is; then what is half typed.
    pub fn status_line(&mut self, ui: &mut Ui, bar: Rect) {
        let t = th();
        let modal = self.s.modal.clone();
        ui.painter().rect_filled(bar, CornerRadius::ZERO, t.panel);
        let mut x = bar.left() + 4.0;
        let y = bar.center().y;
        let mode = text(&modal["mode"]);
        // The view that has the keys, as the terminal's status line says.
        let name = match modal["focused"].as_str() {
            Some(view) if !view.is_empty() => format!("{}·{view}", text(&modal["name"])),
            _ => text(&modal["name"]),
        };
        let w = widgets::text_width(ui, &name, semi(T_MICRO)) + 12.0;
        let chip = Rect::from_min_size(pos2(x, y - 8.0), vec2(w, 16.0));
        ui.painter().rect_filled(chip, CornerRadius::same(3), mode_colour(&mode));
        ui.painter().text(chip.center(), Align2::CENTER_CENTER, &name, semi(T_MICRO), t.on_hue);
        x = chip.right() + 10.0;
        let recording = text(&modal["recording"]);
        if !recording.is_empty() {
            let said = format!("recording @{recording}");
            ui.painter().text(pos2(x, y), Align2::LEFT_CENTER, &said, semi(T_SMALL), t.rec);
            x += widgets::text_width(ui, &said, semi(T_SMALL)) + 10.0;
        }
        // A render under way: how far it is, and a way to stop it.
        let render = &modal["render"];
        if render.is_object() {
            let fraction = number(&render["fraction"]).clamp(0.0, 1.0);
            let file = render["path"].as_str().and_then(|p| p.rsplit('/').next()).unwrap_or("");
            let said = format!("{}{file}  {}%", if render["stage"] == "encoding" { "Encoding " } else { "Rendering " }, (fraction * 100.0).round());
            ui.painter().text(pos2(x, y), Align2::LEFT_CENTER, &said, semi(T_SMALL), t.text);
            x += widgets::text_width(ui, &said, semi(T_SMALL)) + 6.0;
            let well = Rect::from_min_size(pos2(x, y - 3.0), vec2(120.0, 6.0));
            ui.painter().rect_filled(well, CornerRadius::same(3), t.well);
            ui.painter().rect_filled(Rect::from_min_size(well.min, vec2(120.0 * fraction, 6.0)), CornerRadius::same(3), t.select);
            x = well.right() + 6.0;
            let w = widgets::button_width(ui, "Cancel", false, 18.0);
            if widgets::button(ui, Rect::from_min_size(pos2(x, y - 9.0), vec2(w, 18.0)), Id::unique("render-cancel-bar"), None, "Cancel", Look::quiet()).clicked() {
                self.command("render.cancel");
            }
            x += w + 10.0;
        }
        // Waiting for a controller to be moved.
        let learning = text(&modal["learning"]);
        if !learning.is_empty() {
            let said = format!("LEARN  move a knob or fader for {learning}");
            ui.painter().text(pos2(x, y), Align2::LEFT_CENTER, &said, semi(T_SMALL), t.rec);
            x += widgets::text_width(ui, &said, semi(T_SMALL)) + 6.0;
            let w = widgets::button_width(ui, "Cancel", false, 18.0);
            if widgets::button(ui, Rect::from_min_size(pos2(x, y - 9.0), vec2(w, 18.0)), Id::unique("learn-cancel"), None, "Cancel", Look::quiet()).clicked() {
                self.command("learn.cancel");
            }
            x += w + 10.0;
        }
        // From the right: what is half typed, the quickfix count, a note on
        // the prompt.
        let mut right = bar.right() - 10.0;
        let pending = text(&modal["pending"]);
        if !pending.is_empty() {
            ui.painter().text(pos2(right, y), Align2::RIGHT_CENTER, &pending, mono_medium(T_SMALL), t.select);
            right -= widgets::text_width(ui, &pending, mono_medium(T_SMALL)) + 10.0;
        }
        let qf = text(&modal["qf"]["text"]);
        if !qf.is_empty() {
            let colour = match int(&modal["qf"]["level"]) {
                2 => t.error,
                1 => t.warn,
                _ => t.text_2,
            };
            ui.painter().text(pos2(right, y), Align2::RIGHT_CENTER, &qf, mono(T_SMALL), colour);
            right -= widgets::text_width(ui, &qf, mono(T_SMALL)) + 10.0;
        }
        let prompt = &modal["prompt"];
        // A prompt drawn beside what it is about (a notation popover) is not
        // shown a second time here.
        let prompt_open = prompt.is_object() && prompt["anchored"] != true;
        let note = text(&prompt["note"]);
        if prompt_open && !note.is_empty() {
            let colour = if prompt["note_level"] == "error" { t.warn } else { t.text_2 };
            ui.painter().text(pos2(right, y), Align2::RIGHT_CENTER, &note, sans(T_SMALL), colour);
            right -= widgets::text_width(ui, &note, sans(T_SMALL)) + 10.0;
        }
        let room = (right - x).max(0.0);
        // What the pointer is over: in the window's own drawing, or in a
        // pane the kernel draws.
        let hint = widgets::take_hint();
        let hint = if hint.is_empty() { text(&modal["hint"]) } else { hint };
        let message = self.status_message();
        let keys = rows(&modal["keys"]);
        if prompt_open {
            let line = format!("{}{}▏{}", text(&prompt["prompt"]), text(&prompt["before"]), text(&prompt["after"]));
            widgets::text_in(ui, pos2(x, y), &line, mono(T_BASE), t.text, room);
        } else if let Some((message, level)) = message {
            let colour = match level {
                2 => t.error,
                1 => t.warn,
                _ => t.text,
            };
            widgets::text_in(ui, pos2(x, y), &message, sans(T_SMALL), colour, room);
        } else if !hint.is_empty() {
            widgets::text_in(ui, pos2(x, y), &hint, sans(T_SMALL), t.text_2, room);
        } else if !keys.is_empty() {
            // The keys worth knowing in this view, when nothing else has the line.
            let painter = ui.painter().with_clip_rect(Rect::from_min_max(pos2(x, bar.top()), pos2(right, bar.bottom())));
            for k in keys {
                let (key, desc) = (text(&k["key"]), text(&k["desc"]));
                painter.text(pos2(x, y), Align2::LEFT_CENTER, &key, mono_medium(T_SMALL), t.select);
                x += widgets::text_width(ui, &key, mono_medium(T_SMALL)) + 5.0;
                painter.text(pos2(x, y), Align2::LEFT_CENTER, &desc, sans(T_SMALL), t.text_2);
                x += widgets::text_width(ui, &desc, sans(T_SMALL)) + 14.0;
                if x > right {
                    break;
                }
            }
        }
    }

    /// What is drawn over the window for the keyboard: the command line's
    /// candidates, the keys that can follow, a page the kernel draws.
    pub fn overlays(&mut self, ui: &mut Ui, screen: Rect, status: Rect) {
        let t = th();
        let ctx = ui.ctx().clone();
        let modal = self.s.modal.clone();
        let prompt = &modal["prompt"];
        let matches = rows(&prompt["matches"]["items"]);
        if prompt.is_object() && prompt["anchored"] != true && !matches.is_empty() {
            // Columns as wide as the longest entry shown.
            let widest = |key: &str, font: egui::FontId| {
                matches.iter().map(|m| widgets::text_width(ui, &text(&m[key]), font.clone())).fold(0.0, f32::max)
            };
            let label_w = widest("label", mono(T_SMALL)).clamp(80.0, screen.width() / 3.0);
            let desc_w = widest("desc", sans(T_SMALL));
            let width = (label_w + 24.0 + desc_w + 16.0).max(320.0).min(screen.width() - 16.0);
            let height = matches.len() as f32 * 20.0 + 8.0;
            let rect = Rect::from_min_size(pos2(screen.left() + 8.0, status.top() - 2.0 - height), vec2(width, height));
            let chosen = int(&prompt["matches"]["chosen"]);
            let total = int(&prompt["matches"]["total"]);
            egui::Area::new(Id::unique("completions")).order(Order::Foreground).fixed_pos(rect.min).interactable(false).show(&ctx, |ui| {
                ui.painter().rect(rect, CornerRadius::same(6), t.card, Stroke::new(1.0, t.card_line), StrokeKind::Inside);
                for (i, m) in matches.iter().enumerate() {
                    let row = Rect::from_min_size(pos2(rect.left() + 4.0, rect.top() + 4.0 + i as f32 * 20.0), vec2(width - 8.0, 20.0));
                    let on = i as i64 + 1 == chosen;
                    if on {
                        ui.painter().rect_filled(row, CornerRadius::same(3), alpha(t.select, 0.15));
                    }
                    widgets::text_in(ui, pos2(row.left() + 8.0, row.center().y), &text(&m["label"]), mono(T_SMALL), if on { t.select } else { t.text }, label_w);
                    let dx = row.left() + 8.0 + label_w + 16.0;
                    widgets::text_in(ui, pos2(dx, row.center().y), &text(&m["desc"]), sans(T_SMALL), t.text_2, row.right() - dx - 8.0);
                }
                if total > matches.len() as i64 {
                    ui.painter().text(rect.right_bottom() - vec2(8.0, 2.0), Align2::RIGHT_BOTTOM, format!("{total} matches"), sans(T_MICRO), t.text_3);
                }
            });
        }
        // The keys that can follow a half-typed command.
        let hints = rows(&modal["hints"]["items"]);
        if !hints.is_empty() {
            let columns = (((screen.width() - 40.0) / 270.0).floor() as usize).max(1);
            let per = hints.len().div_ceil(columns);
            let height = 34.0 + per as f32 * 19.0;
            let rect = Rect::from_min_size(pos2(screen.left() + 8.0, screen.bottom() - height - 34.0), vec2(screen.width() - 16.0, height));
            egui::Area::new(Id::unique("hints")).order(Order::Foreground).fixed_pos(rect.min).interactable(false).show(&ctx, |ui| {
                ui.painter().rect(rect, CornerRadius::same(6), t.card, Stroke::new(1.0, t.card_line), StrokeKind::Inside);
                ui.painter().text(rect.min + vec2(12.0, 7.0), Align2::LEFT_TOP, text(&modal["hints"]["title"]), semi(T_SMALL), t.text_2);
                for (i, h) in hints.iter().enumerate() {
                    let at = rect.min + vec2(12.0 + (i / per) as f32 * 270.0, 26.0 + (i % per) as f32 * 19.0 + 9.5);
                    widgets::text_in(ui, pos2(at.x, at.y), &text(&h["key"]), mono_medium(T_BASE), t.select, 62.0);
                    widgets::text_in(ui, pos2(at.x + 66.0, at.y), &text(&h["desc"]), sans(T_BASE), t.text, 196.0);
                }
            });
        }
        // A floating page from the kernel: help, a list, a picker.
        self.float_page(ui, screen);
    }

    fn float_page(&mut self, ui: &mut Ui, screen: Rect) {
        let t = th();
        let ctx = ui.ctx().clone();
        // How many columns and lines of text the page has room for: the
        // kernel draws it to this size.
        let char_w = widgets::text_width(ui, "M", mono(12.0)).max(1.0);
        let line_h = ui.fonts_mut(|f| f.row_height(&mono(12.0)));
        let cols = ((screen.width() - 80.0) / char_w).floor().max(20.0) as usize;
        let lines = ((screen.height() - 112.0) / line_h).floor().max(5.0) as usize;
        if (cols, lines) != self.float_size {
            self.float_size = (cols, lines);
            if self.float.is_some() {
                let page = self.ask("return paw.frontend.float(...)", json!([cols, lines]));
                self.float = Some((text(&page["title"]), rows(&page["lines"]).iter().map(text).collect()));
            }
        }
        let Some((title, page)) = self.float.clone() else { return };
        let width = page.iter().map(|l| l.chars().count()).max().unwrap_or(0) as f32 * char_w + 28.0;
        let width = width.clamp(300.0, screen.width() - 40.0);
        let height = (page.len().max(1) as f32 * line_h + 52.0).min(screen.height() - 60.0);
        let card = Rect::from_center_size(screen.center(), vec2(width, height));
        let mut events = Vec::new();
        let mut window = false;
        egui::Area::new(Id::unique("float-backdrop")).order(Order::Middle).fixed_pos(screen.min).show(&ctx, |ui| {
            ui.expand_to_include_rect(screen);
            ui.painter().rect_filled(screen, CornerRadius::ZERO, Color32::from_black_alpha(0xaa));
            let response = ui.interact(screen, Id::unique("float-backdrop-touch"), Sense::click());
            if response.clicked() && !card.contains(response.interact_pointer_pos().unwrap_or_default()) {
                events.push(None);
            }
        });
        egui::Area::new(Id::unique("float-card")).order(Order::Foreground).fixed_pos(card.min).show(&ctx, |ui| {
            ui.expand_to_include_rect(card);
            ui.painter().rect(card, CornerRadius::same(6), t.card, Stroke::new(1.0, t.card_line), StrokeKind::Inside);
            ui.painter().text(card.min + vec2(14.0, 10.0), Align2::LEFT_TOP, &title, semi(T_TITLE), t.text);
            let body = Rect::from_min_max(card.min + vec2(14.0, 36.0), card.max - vec2(14.0, 8.0));
            let painter = ui.painter().with_clip_rect(body);
            for (i, line) in page.iter().enumerate() {
                painter.text(pos2(body.left(), body.top() + i as f32 * line_h), Align2::LEFT_TOP, line, mono(12.0), t.text);
            }
            // Rows of a picker are clicked and scrolled; a double click chooses.
            let response = ui.interact(body, Id::unique("float-body"), Sense::click());
            let place = |p: Pos2| {
                (((p.y - body.top()) / line_h).floor() as i64 + 1, ((p.x - body.left()) / char_w).floor() as i64 + 1)
            };
            if ui.input(|i| i.pointer.primary_pressed())
                && let Some(p) = ui.input(|i| i.pointer.interact_pos()).filter(|p| body.contains(*p))
            {
                events.push(Some(("down", place(p))));
            }
            if response.hovered() {
                let dy = widgets::wheel_y(ui);
                if dy != 0.0
                    && let Some(p) = response.hover_pos()
                {
                    events.push(Some((if dy < 0.0 { "scroll_down" } else { "scroll_up" }, place(p))));
                }
            }
            let label = "Open in a window";
            let w = widgets::button_width(ui, label, false, 22.0);
            let button = Rect::from_min_size(pos2(card.right() - w - 8.0, card.top() + 6.0), vec2(w, 22.0));
            window = widgets::button(ui, button, Id::unique("float-window"), None, label, Look::quiet()).clicked();
        });
        for event in events {
            match event {
                None => self.feed("<Esc>"),
                Some((kind, (line, col))) => self.pass("float_pointer", json!([kind, line, col])),
            }
        }
        if window {
            self.command("view.window");
        }
    }
}
