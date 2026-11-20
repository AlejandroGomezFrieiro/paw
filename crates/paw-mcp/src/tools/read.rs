//! The tools that read the project: what is there, what it says, what is wrong.

use std::fmt::Write as _;

use serde_json::{Map, Value, json};

use super::{Args, Effect, Outcome, Reply, Run, Tool, Tools, enrich, items};
use crate::format;
use crate::music::{self, Meter, num};
use crate::schema::*;

pub(super) fn tools() -> Vec<Tool> {
    vec![
        Tool {
            name: "get_project",
            title: "Read the project",
            description: "The whole session in one call: name, file, tempo, time signature, key, length, transport, markers and regions, and every track with its id, volume, pan, routing and sends, devices (id, kind), clips (id, position, length, note count and range) and automation lanes. Start here; ids it shows are what the other tools take. The result is also given as structured JSON. Reads only.".into(),
            schema: obj(json!({}), &[]),
            effect: Effect::Reads,
            run: Run::Call(Tools::get_project),
        },
        Tool {
            name: "get_track",
            title: "Read a track in detail",
            description: "One track in full: settings, routing, sends, every device with its parameters' current values, every clip, automation lanes with their points, and the engine's live meter for the track (-120 dB when nothing is playing: use render to measure a track's level). Reads only.".into(),
            schema: obj(json!({"track": track_ref("The track")}), &["track"]),
            effect: Effect::Reads,
            run: Run::Call(Tools::get_track),
        },
        Tool {
            name: "get_clip",
            title: "Read a clip's notes",
            description: "A clip and its notes (id, pitch, start and length in beats from the clip's start, velocity), or an audio clip's file, offset and gain. Note ids are what edit_clip takes to change one note. Filter a big clip with `from`, `to` and `pitches`. Reads only.".into(),
            schema: {
                let mut properties = note_filter();
                properties["clip"] = json!({"type": "integer", "description": "Clip id"});
                obj(properties, &["clip"])
            },
            effect: Effect::Reads,
            run: Run::Call(Tools::get_clip),
        },
        Tool {
            name: "get_device",
            title: "Read a device's parameters",
            description: "A device's parameters: key, name, current value, range, default, unit, and the choices of switch-like ones. Every device also has fx_wet and fx_gain (the dry/wet mix and gain around it). Plugins can have hundreds of parameters: pass `filter` to see only matching ones. Reads only.".into(),
            schema: obj(json!({
                "device": {"type": "integer", "description": "Device id"},
                "filter": {"type": "string", "description": "Only parameters whose key or name contains this text"}
            }), &["device"]),
            effect: Effect::Reads,
            run: Run::Call(Tools::get_device),
        },
        Tool {
            name: "find_devices",
            title: "Search addable devices",
            description: "Search the devices and plugins (CLAP, LV2, VST3) that can be added to a track: every word must appear in the kind, name, vendor, category or format. Built-in devices come first: synth (subtractive synth), drums (General MIDI drum kit: 36 kick, 38 snare, 39 clap, 40 snare 2, 42 closed hat, 44 pedal hat, 46 open hat), gain, delay. Use it before add_device when you want a particular plugin. Reads only.".into(),
            schema: obj(json!({
                "query": {"type": "string", "description": "Words to look for, such as \"reverb\", \"eq\", \"surge\". Empty lists everything"},
                "format": {"type": "string", "enum": ["builtin", "clap", "lv2", "vst3"], "description": "Only this format"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 200, "description": "At most this many (default 25)"},
                "params": {"type": "boolean", "description": "Also list each match's parameters (default false)"}
            }), &[]),
            effect: Effect::Reads,
            run: Run::Call(Tools::find_devices),
        },
        Tool {
            name: "get_status",
            title: "Transport and messages",
            description: "Where the transport is (playing, position, loop, metronome), the audio engine (backend, sample rate, CPU, dropouts), whether the project has unsaved changes, and paw's recent messages, warnings and errors. Reads only.".into(),
            schema: obj(json!({"messages": {"type": "integer", "minimum": 0, "maximum": 100, "description": "How many recent messages (default 10)"}}), &[]),
            effect: Effect::Reads,
            run: Run::Call(Tools::get_status),
        },
        Tool {
            name: "find",
            title: "Find tracks, clips, notes by a query",
            description: "Find things in the project with paw's query language, a CSS selector over the project tree. Kinds: track, group, clip, note, cc, device, lane, point, marker, region. Tests in brackets: `[name~=pizz]` (regex), `=`, `!=`, `<`, `>=`, `^=` (starts with), `$=`, `*=`; pitches as c4, c#4 or 60; `a > b` is a b right inside an a, `a b` one anywhere inside it, `,` joins queries. Examples: `note[pitch>=c5]`, `clip[name~=riff] > note[vel>100]`, `track:has(device[kind=synth])`, `clip:has(note[pitch=c#5])`, `track[mute]`. Returns each match's kind, id, track, clip and a one-line description. Reads only.".into(),
            schema: obj(json!({
                "query": {"type": "string", "description": "The query, such as `clip[name~=riff] > note[pitch>=c5]`"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 500, "description": "At most this many matches (default 50)"}
            }), &["query"]),
            effect: Effect::Reads,
            run: Run::Call(Tools::find),
        },
        Tool {
            name: "diagnose",
            title: "Check the project for problems",
            description: "Look for what makes a project not sound as meant: empty tracks, MIDI tracks with no (or a bypassed) instrument, which are silent, empty clips, notes that start after their clip ends, plugins that did not load, sends and outputs to tracks that are gone or muted, automation outside its range, clips on the master, a soloed track; and what other tools in paw have reported. With `measure` it also renders the song and flags a silent mix, clipping, an over-hot true peak and tracks that clip, and gives the loudness. Returns findings with a severity (error, warning, info), a rule name and the track, clip or device concerned. Reads only (the render is not written).".into(),
            schema: obj(json!({
                "track": track_ref("Only this track (default every track and the master)"),
                "measure": {"type": "boolean", "description": "Also render and measure the whole song for clipping, silence and loudness (takes as long as a render; default false)"}
            }), &[]),
            effect: Effect::Reads,
            run: Run::Call(Tools::diagnose),
        },
    ]
}

impl Tools {
    fn get_project(&mut self, _a: &Args) -> Outcome {
        let r = self.lua("project", json!({}))?;
        let meter = Meter::from_project(&r["project"]);
        Ok(Self::reply(format::project(&r["project"]), &r, meter))
    }

    fn get_track(&mut self, a: &Map<String, Value>) -> Outcome {
        let meter = self.meter()?;
        let r = self.lua("track", json!({ "track": a["track"] }))?;
        let mut out = String::new();
        format::track(&mut out, &r["track"], meter, true);
        Ok(Self::reply(out, &r, meter))
    }

    fn get_clip(&mut self, a: &Map<String, Value>) -> Outcome {
        let meter = self.meter()?;
        let mut filter = Map::new();
        for key in ["from", "to"] {
            if let Some(v) = a.get(key) {
                filter.insert(key.into(), json!(music::position(v, meter, key)?));
            }
        }
        if let Some(p) = a.get("pitches") {
            filter.insert("pitches".into(), json!(music::pitches(p)?));
        }
        let filter = (!filter.is_empty()).then_some(Value::Object(filter));
        let r = self.lua("clip", json!({ "clip": a["clip"], "filter": filter }))?;
        let mut out = String::new();
        format::clip(&mut out, &r["clip"], meter);
        Ok(Self::reply(out, &r, meter))
    }

    fn get_device(&mut self, a: &Map<String, Value>) -> Outcome {
        let r = self.lua(
            "device",
            json!({ "device": a["device"], "filter": a.get("filter") }),
        )?;
        let mut out = String::new();
        let d = &r["device"];
        format::device(&mut out, d, "", usize::MAX);
        if let Some(track) = d["track_name"].as_str() {
            let _ = writeln!(out, "on track \"{track}\"");
        }
        Ok(Self::reply(out, &r, Meter::default()))
    }

    fn find_devices(&mut self, a: &Map<String, Value>) -> Outcome {
        let r = self.lua("find_devices", Value::Object(a.clone()))?;
        let devices = items(&r["devices"]);
        let total = r["total"].as_u64().unwrap_or(0);
        let mut out = format!(
            "{} of {} device kinds match{}:\n",
            total,
            r["all"].as_u64().unwrap_or(0),
            if (devices.len() as u64) < total {
                format!(
                    " (showing {}; narrow the query or raise limit)",
                    devices.len()
                )
            } else {
                String::new()
            }
        );
        for d in devices {
            let mut extra: Vec<String> = Vec::new();
            for key in ["vendor", "category"] {
                if let Some(v) = d[key].as_str().filter(|v| !v.is_empty()) {
                    extra.push(v.to_string());
                }
            }
            let _ = writeln!(
                out,
                "  {} — {} ({}{}{}) · {} params",
                d["kind"].as_str().unwrap_or(""),
                d["name"].as_str().unwrap_or(""),
                d["format"].as_str().unwrap_or(""),
                if extra.is_empty() { "" } else { ", " },
                extra.join(", "),
                d["params"]
            );
            for p in items(&d["param_info"]) {
                let _ = writeln!(
                    out,
                    "      {} \"{}\" {} to {} (default {})",
                    p["key"].as_str().unwrap_or(""),
                    p["name"].as_str().unwrap_or(""),
                    num(p["min"].as_f64().unwrap_or(0.0)),
                    num(p["max"].as_f64().unwrap_or(0.0)),
                    num(p["default"].as_f64().unwrap_or(0.0))
                );
            }
        }
        Ok(Self::reply(out, &r, Meter::default()))
    }

    fn get_status(&mut self, a: &Map<String, Value>) -> Outcome {
        let r = self.lua("status", json!({ "messages": a.get("messages") }))?;
        let p = &r["project"];
        let meter = Meter::from_project(p);
        let e = &r["engine"];
        let mut out = format::project_header(p, meter);
        let _ = writeln!(
            out,
            "\nTransport: {}",
            format::transport(&r["transport"], meter)
        );
        let _ = writeln!(
            out,
            "Engine: {} backend, {} Hz, buffer {}, CPU {:.0}%, {} dropouts",
            e["backend"].as_str().unwrap_or("?"),
            e["sample_rate"],
            e["buffer_size"],
            e["cpu"].as_f64().unwrap_or(0.0) * 100.0,
            e["xruns"]
        );
        let _ = writeln!(out, "Kernel socket: {}", self.kernel.socket.display());
        if items(&r["messages"]).is_empty() {
            out.push_str("No messages.\n");
        } else {
            format::messages(&mut out, &r["messages"]);
        }
        let mut data = r.clone();
        enrich(&mut data, meter);
        data["socket"] = json!(self.kernel.socket.display().to_string());
        Ok(Reply { text: out, data })
    }

    fn find(&mut self, a: &Map<String, Value>) -> Outcome {
        let r = self.lua("find", Value::Object(a.clone()))?;
        let found = items(&r["found"]);
        let total = r["total"].as_u64().unwrap_or(0);
        let mut out = format!(
            "{total} match{}{}:\n",
            if total == 1 { "" } else { "es" },
            if (found.len() as u64) < total {
                format!(" (showing {}; raise limit or narrow the query)", found.len())
            } else {
                String::new()
            }
        );
        for n in found {
            let _ = writeln!(
                out,
                "  {} [id {}]: {}",
                n["kind"].as_str().unwrap_or(""),
                n["id"],
                n["text"].as_str().unwrap_or("")
            );
        }
        Ok(Self::reply(out, &r, self.meter()?))
    }

    fn diagnose(&mut self, a: &Map<String, Value>) -> Outcome {
        let r = self.lua("diagnose", Value::Object(a.clone()))?;
        let mut out = String::new();
        let findings = items(&r["findings"]);
        let c = &r["counts"];
        if findings.is_empty() {
            out.push_str("No problems found.\n");
        } else {
            let _ = writeln!(
                out,
                "{} error{}, {} warning{}, {} note{}:",
                c["error"],
                if c["error"] == 1 { "" } else { "s" },
                c["warning"],
                if c["warning"] == 1 { "" } else { "s" },
                c["info"],
                if c["info"] == 1 { "" } else { "s" }
            );
        }
        for f in findings {
            let _ = writeln!(
                out,
                "  [{}] {}: {}",
                f["severity"].as_str().unwrap_or(""),
                f["rule"].as_str().unwrap_or(""),
                f["message"].as_str().unwrap_or("")
            );
        }
        if let Some(m) = r["measure"].as_object() {
            let level = |key: &str| m.get(key).and_then(Value::as_f64).map(|v| num((v * 10.0).round() / 10.0));
            let _ = writeln!(
                out,
                "measured: {} LUFS integrated, true peak {} dBTP, sample peak {} dBFS",
                level("integrated").unwrap_or("?".into()),
                level("true_peak").unwrap_or("?".into()),
                level("sample_peak").unwrap_or("?".into())
            );
        }
        let published = items(&r["published"]);
        if !published.is_empty() {
            out.push_str("reported by other tools in paw:\n");
            for p in published {
                let _ = writeln!(
                    out,
                    "  [{}] {}{}",
                    p["severity"].as_str().unwrap_or(""),
                    p["source"]
                        .as_str()
                        .map(|s| format!("{s}: "))
                        .unwrap_or_default(),
                    p["message"].as_str().unwrap_or("")
                );
            }
        }
        Ok(Self::reply(out, &r, Meter::default()))
    }
}
