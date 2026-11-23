//! Kernel data as compact text for a model: ids in brackets, positions in
//! beats with `bar.beat` beside them, levels in dB.

use std::fmt::Write as _;

use serde_json::Value;

use crate::music::{Meter, name, num};

/// The items of a JSON array; an empty Lua table arrives as `{}`, so
/// anything that is not an array is no items.
pub(crate) fn items(value: &Value) -> &[Value] {
    value.as_array().map(Vec::as_slice).unwrap_or(&[])
}

fn f(value: &Value) -> f64 {
    value.as_f64().unwrap_or(0.0)
}

fn s(value: &Value) -> &str {
    value.as_str().unwrap_or("")
}

/// `8 (3.1)`: beats, and where that is in bars.
pub(crate) fn at(beats: f64, meter: &Meter) -> String {
    format!("{} ({})", num(beats), meter.format(beats))
}

/// A length in beats, with bars when it is a whole number of them.
pub(crate) fn span(beats: f64, meter: &Meter) -> String {
    let bars = beats / meter.bar();
    if (bars - bars.round()).abs() < 1e-6 && bars >= 1.0 {
        let n = bars.round() as i64;
        format!(
            "{} beats = {n} bar{}",
            num(beats),
            if n == 1 { "" } else { "s" }
        )
    } else {
        format!("{} beats", num(beats))
    }
}

pub(crate) fn db(value: f64) -> String {
    format!("{} dB", num((value * 10.0).round() / 10.0))
}

pub(crate) fn messages(out: &mut String, list: &Value) {
    let list = items(list);
    if list.is_empty() {
        return;
    }
    out.push_str("paw messages:\n");
    for m in list {
        let level = s(&m["level"]);
        let text = s(&m["text"]);
        let first = text.lines().next().unwrap_or("");
        if level == "info" {
            let _ = writeln!(out, "  {first}");
        } else {
            let _ = writeln!(out, "  [{level}] {first}");
        }
    }
}

/// The loudness a render or a file measured: `loudness: -14.2 LUFS ...`.
pub(crate) fn loudness(l: &Value) -> Option<String> {
    if !l.is_object() {
        return None;
    }
    let level = |key: &str| l[key].as_f64().map(|v| num((v * 10.0).round() / 10.0));
    let Some(integrated) = level("integrated") else {
        return Some("loudness: not measurable (silent, or shorter than 400 ms)\n".into());
    };
    let mut out = format!("loudness: {integrated} LUFS integrated");
    if let Some(v) = level("short_term_max") {
        let _ = write!(out, ", short-term maximum {v} LUFS");
    }
    if let Some(v) = level("lra") {
        let _ = write!(out, ", range {v} LU");
    }
    if let Some(v) = level("true_peak") {
        let _ = write!(out, ", true peak {v} dBTP");
    }
    out.push('\n');
    Some(out)
}

pub(crate) fn transport(t: &Value, meter: &Meter) -> String {
    let mut out = format!(
        "{} at {}",
        if t["playing"].as_bool() == Some(true) {
            "playing"
        } else {
            "stopped"
        },
        at(f(&t["position"]), meter)
    );
    let _ = write!(
        out,
        " · loop {} {}–{}",
        if t["loop_enabled"].as_bool() == Some(true) {
            "on"
        } else {
            "off"
        },
        at(f(&t["loop_start"]), meter),
        at(f(&t["loop_end"]), meter)
    );
    if t["metronome"].as_bool() == Some(true) {
        out.push_str(" · metronome on");
    }
    if t["recording"].as_bool() == Some(true) {
        out.push_str(" · RECORDING");
    }
    out
}

pub(crate) fn project_header(p: &Value, meter: &Meter) -> String {
    let file = match p["path"].as_str() {
        Some(path) => format!("file {path}"),
        None => "never saved".into(),
    };
    format!(
        "Project \"{}\" ({file}{}) · {} BPM · {}/{}{} · length {}",
        s(&p["name"]),
        if p["modified"].as_bool() == Some(true) {
            ", unsaved changes"
        } else {
            ""
        },
        num(f(&p["tempo"])),
        meter.num,
        meter.den,
        p["key"]
            .as_str()
            .map(|key| format!(" · key {key}"))
            .unwrap_or_default(),
        span(f(&p["length"]), meter)
    ) + &tempo_changes(p, meter)
}

/// " · then 90 BPM at 5.1 (ramping to the next), 6/8 at 9.1" for a song
/// whose tempo or signature changes along the way.
fn tempo_changes(p: &Value, meter: &Meter) -> String {
    let mut changes: Vec<(f64, String)> = Vec::new();
    for c in items(&p["tempo_changes"]) {
        let ramp = if c["ramp"].as_bool() == Some(true) {
            ", ramping to the next"
        } else {
            ""
        };
        let at = f(&c["beat"]);
        changes.push((
            at,
            format!("{} BPM at {}{ramp}", num(f(&c["bpm"])), meter.format(at)),
        ));
    }
    for c in items(&p["sig_changes"]) {
        let at = f(&c["beat"]);
        changes.push((
            at,
            format!("{}/{} at {}", c["num"], c["den"], meter.format(at)),
        ));
    }
    if changes.is_empty() {
        return String::new();
    }
    changes.sort_by(|a, b| a.0.total_cmp(&b.0));
    let ramp = if p["tempo_ramp"].as_bool() == Some(true) {
        " (ramping from the start)"
    } else {
        ""
    };
    let list: Vec<String> = changes.into_iter().map(|c| c.1).collect();
    format!("{ramp} · then {}", list.join(", "))
}

pub(crate) fn project(p: &Value) -> String {
    let meter = Meter::from_project(p);
    let mut out = project_header(p, &meter);
    let _ = writeln!(out, "\nTransport: {}", transport(&p["transport"], &meter));
    let parts = items(&p["parts"]);
    let _ = writeln!(out, "Parts ({}):", parts.len());
    for t in parts {
        part(&mut out, t, &meter, false);
    }
    part(&mut out, &p["master"], &meter, false);
    let markers = items(&p["markers"]);
    if !markers.is_empty() {
        let _ = writeln!(out, "Markers and regions ({}):", markers.len());
        for m in markers {
            let _ = writeln!(out, "  {}", marker_line(m, &meter));
        }
    }
    out
}

/// `[id 2] region "Chorus" at 9.1, 8 beats = 2 bars, to 11.1`.
pub(crate) fn marker_line(m: &Value, meter: &Meter) -> String {
    let beat = f(&m["beat"]);
    let mut line = format!(
        "[id {}] {} \"{}\" at {}",
        f(&m["id"]),
        if m["region"].as_bool() == Some(true) {
            "region"
        } else {
            "marker"
        },
        s(&m["name"]),
        at(beat, meter)
    );
    if let Some(length) = m["length"].as_f64() {
        let _ = write!(
            line,
            ", {}, to {}",
            span(length, meter),
            meter.format(beat + length)
        );
    }
    line
}

fn part_line(t: &Value, meter: &Meter) -> String {
    let _ = meter;
    let mut line = if t["master"].as_bool() == Some(true) {
        "Master [id 0]".to_string()
    } else {
        format!(
            "{}. \"{}\" [id {}]",
            f(&t["index"]),
            s(&t["name"]),
            f(&t["id"])
        )
    };
    let _ = write!(
        line,
        " vol {}, pan {}",
        db(f(&t["volume"])),
        num(f(&t["pan"]))
    );
    if t["master"].as_bool() != Some(true) {
        match t["output"].as_f64() {
            Some(id) => {
                let _ = write!(line, ", out → \"{}\" [id {id}]", s(&t["output_name"]));
            }
            None => line.push_str(", out → master"),
        }
    }
    for (flag, label) in [("mute", "MUTED"), ("solo", "SOLO"), ("armed", "ARMED")] {
        if t[flag].as_bool() == Some(true) {
            let _ = write!(line, ", {label}");
        }
    }
    if let Some(input) = t["input"].as_str() {
        let _ = write!(line, ", input {input}");
    }
    line
}

pub(crate) fn part(out: &mut String, t: &Value, meter: &Meter, detail: bool) {
    let _ = writeln!(out, "{}", part_line(t, meter));
    let sends = items(&t["sends"]);
    if !sends.is_empty() {
        let list: Vec<String> = sends
            .iter()
            .map(|send| {
                format!(
                    "\"{}\" [id {}] {}",
                    s(&send["name"]),
                    f(&send["target"]),
                    db(f(&send["level"]))
                )
            })
            .collect();
        let _ = writeln!(out, "   sends: {}", list.join(", "));
    }
    let devices = items(&t["devices"]);
    if devices.is_empty() {
        out.push_str("   devices: none\n");
    } else if detail {
        out.push_str("   devices:\n");
        for d in devices {
            device(out, d, "     ", 32);
        }
    } else {
        let list: Vec<String> = devices.iter().map(device_short).collect();
        let _ = writeln!(out, "   devices: {}", list.join(", "));
    }
    let clips = items(&t["clips"]);
    if !clips.is_empty() {
        let limit = if detail { usize::MAX } else { 16 };
        out.push_str("   clips:\n");
        for c in clips.iter().take(limit) {
            let _ = writeln!(out, "     {}", clip_line(c, meter));
        }
        if clips.len() > limit {
            let _ = writeln!(
                out,
                "     ... and {} more (get_part lists them all)",
                clips.len() - limit
            );
        }
    }
    for l in items(&t["lanes"]) {
        let _ = writeln!(out, "   automation: {}", lane(l, meter));
    }
    if detail && t["meter"].is_object() {
        let _ = writeln!(
            out,
            "   meter now: left {}, right {} (the engine's live peak: -120 dB when nothing plays)",
            db(f(&t["meter"]["left"])),
            db(f(&t["meter"]["right"]))
        );
    }
}

fn device_short(d: &Value) -> String {
    let mut text = format!("[id {}] {} ({})", f(&d["id"]), s(&d["name"]), s(&d["kind"]));
    if d["bypass"].as_bool() == Some(true) {
        text.push_str(" BYPASSED");
    }
    if d["missing"].as_bool() == Some(true) {
        text.push_str(" NOT LOADED");
    }
    text
}

pub(crate) fn clip_line(c: &Value, meter: &Meter) -> String {
    let start = f(&c["start"]);
    let length = f(&c["length"]);
    let mut line = format!(
        "[id {}] \"{}\" {} at {}, {} long, to {}",
        f(&c["id"]),
        s(&c["name"]),
        s(&c["kind"]),
        at(start, meter),
        span(length, meter),
        meter.format(start + length)
    );
    if s(&c["kind"]) == "midi" {
        let count = f(&c["note_count"]) as i64;
        let _ = write!(line, ", {count} note{}", if count == 1 { "" } else { "s" });
        if let (Some(lo), Some(hi)) = (c["low"].as_u64(), c["high"].as_u64()) {
            if lo == hi {
                let _ = write!(line, " ({})", name(lo as u8));
            } else {
                let _ = write!(line, " ({}–{})", name(lo as u8), name(hi as u8));
            }
        }
    } else {
        let _ = write!(
            line,
            ", file {}, offset {} s, gain {}",
            s(&c["file"]),
            num(f(&c["offset"])),
            db(f(&c["gain"]))
        );
    }
    if c["muted"].as_bool() == Some(true) {
        line.push_str(", MUTED");
    }
    line
}

/// A clip, and its notes when they are there.
pub(crate) fn clip(out: &mut String, c: &Value, meter: &Meter) {
    let _ = writeln!(out, "{}", clip_line(c, meter));
    if let Some(part) = c["part_name"].as_str() {
        let _ = writeln!(out, "on part \"{part}\" [id {}]", f(&c["part"]));
    }
    let notes = items(&c["notes"]);
    if c["filtered"].as_bool() == Some(true) {
        let _ = writeln!(
            out,
            "{} of {} notes match the filter",
            notes.len(),
            f(&c["note_count"])
        );
    }
    if notes.is_empty() {
        return;
    }
    out.push_str(
        "notes: pitch start length velocity (beats from the clip's start; bar.beat within the clip) [note id]\n",
    );
    for n in notes {
        let start = f(&n["start"]);
        let _ = write!(
            out,
            "  {} {} {} {}  ({})",
            name(n["pitch"].as_u64().unwrap_or(0) as u8),
            num(start),
            num(f(&n["length"])),
            f(&n["velocity"]),
            meter.format(start)
        );
        if let Some(lyric) = n["lyric"].as_str() {
            let _ = write!(out, " lyric \"{lyric}\"");
        }
        if let Some(id) = n["id"].as_u64() {
            let _ = write!(out, " [id {id}]");
        }
        out.push('\n');
    }
}

fn param_value(p: &Value) -> String {
    let value = f(&p["value"]);
    let choices = items(&p["choices"]);
    if !choices.is_empty() {
        let index = value.round() as usize;
        let current = choices.get(index).and_then(Value::as_str).unwrap_or("?");
        let all: Vec<&str> = choices.iter().map(s).collect();
        return format!("{current} ({}; one of {})", num(value), all.join("|"));
    }
    let unit = s(&p["unit"]);
    format!(
        "{}{}{} (range {} to {}, default {})",
        num(value),
        if unit.is_empty() { "" } else { " " },
        unit,
        num(f(&p["min"])),
        num(f(&p["max"])),
        num(f(&p["default"]))
    )
}

/// A device with its parameters, at most `limit` of them.
pub(crate) fn device(out: &mut String, d: &Value, indent: &str, limit: usize) {
    let _ = writeln!(
        out,
        "{indent}{} · {} format · position {} in the chain of part [id {}]",
        device_short(d),
        s(&d["format"]),
        f(&d["index"]),
        f(&d["part"])
    );
    let params = items(&d["params"]);
    let total = d["param_count"].as_u64().unwrap_or(params.len() as u64) as usize;
    if params.is_empty() {
        if total > 0 {
            let _ = writeln!(out, "{indent}  {total} parameters (get_device lists them)");
        } else if d["filtered"].as_bool() == Some(true) {
            let _ = writeln!(out, "{indent}  no parameter matches the filter");
        } else {
            let _ = writeln!(out, "{indent}  no parameters");
        }
        return;
    }
    if params.len() > limit {
        let _ = writeln!(
            out,
            "{indent}  {} parameters; get_device lists them (with a filter for big plugins)",
            params.len()
        );
        return;
    }
    if d["filtered"].as_bool() == Some(true) || d["only_changed"].as_bool() == Some(true) {
        let _ = writeln!(out, "{indent}  {} of {total} parameters:", params.len());
    }
    for p in params {
        let key = s(&p["key"]);
        let pname = s(&p["name"]);
        let label = if pname.eq_ignore_ascii_case(key) || pname.is_empty() {
            key.to_string()
        } else {
            format!("{key} \"{pname}\"")
        };
        let _ = writeln!(out, "{indent}  {label}: {}", param_value(p));
    }
}

pub(crate) fn lane(l: &Value, meter: &Meter) -> String {
    let target = match s(&l["target"]) {
        "param" => format!(
            "device [id {}] parameter {}",
            f(&l["device"]),
            s(&l["param"])
        ),
        other => other.to_string(),
    };
    let mut text = format!(
        "[id {}] {target}, {}, range {} to {}",
        f(&l["id"]),
        if l["enabled"].as_bool() == Some(false) {
            "OFF"
        } else {
            "on"
        },
        num(f(&l["min"]).max(-1e9)),
        num(f(&l["max"]).min(1e9)),
    );
    let points = items(&l["points"]);
    if points.is_empty() {
        let count = f(&l["point_count"]) as i64;
        let _ = write!(text, ", {count} point{}", if count == 1 { "" } else { "s" });
    } else {
        let list: Vec<String> = points
            .iter()
            .take(64)
            .map(|p| {
                let beat = f(&p[0]);
                format!("{}→{}", at(beat, meter), num(f(&p[1])))
            })
            .collect();
        let _ = write!(
            text,
            ", points (beat (bar.beat)→value): {}",
            list.join(", ")
        );
        if points.len() > 64 {
            let _ = write!(text, " ... and {} more", points.len() - 64);
        }
    }
    text
}
