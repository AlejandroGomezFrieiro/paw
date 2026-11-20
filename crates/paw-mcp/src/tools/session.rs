//! The tools for the transport, the undo history and the project file.

use std::fmt::Write as _;

use serde_json::{Map, Value, json};

use super::{Effect, Outcome, Run, Tool, ToolError, Tools, err, items};
use crate::format;
use crate::music::{self, Meter};
use crate::schema::*;

pub(super) fn tools() -> Vec<Tool> {
    vec![
        Tool {
            name: "transport",
            title: "Play, stop, seek, loop",
            description: "Control playback: play, stop, move the playhead, set and toggle the loop (by position, or `loop_marker` to loop a region, or a marker up to the next marker), the metronome. Playback is heard on paw's audio device (nothing with the null backend); to check how something sounds, use render instead. Not part of undo.".into(),
            schema: obj(json!({
                "action": {"type": "string", "enum": ["play", "stop"], "description": "Start or stop playback (after the other settings are applied)"},
                "position": position("Move the playhead here"),
                "loop": {"type": "boolean", "description": "Turn looping on or off"},
                "loop_start": position("Loop start"),
                "loop_end": position("Loop end"),
                "loop_marker": marker_ref("Loop this region (or the stretch from this marker to the next), and turn looping on"),
                "metronome": {"type": "boolean", "description": "Metronome on or off"}
            }), &[]),
            effect: Effect::Changes,
            run: Run::Call(Tools::transport),
        },
        Tool {
            name: "undo",
            title: "Undo, redo, history",
            description: "Undo the last change (or `steps` changes), or redo with redo=true; the result says what each step was (\"mcp: add_track Bass\"; a change made by a person in paw says so). With nothing to undo it fails. With list=true it changes nothing and lists the history, newest first, and what redo would bring back. Every writing tool call is one named step, and so is a batch.".into(),
            schema: obj(json!({
                "steps": {"type": "integer", "minimum": 1, "maximum": 100, "description": "How many steps (default 1)"},
                "redo": {"type": "boolean", "description": "Redo instead of undo"},
                "list": {"type": "boolean", "description": "List the history instead of undoing"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 200, "description": "With list: how many entries (default 20)"}
            }), &[]),
            effect: Effect::Changes,
            run: Run::Call(Tools::undo),
        },
        Tool {
            name: "project_file",
            title: "Save, open, new",
            description: "Save the project (to its file, or to `path`), open a project file, or start a new empty one. Opening and new replace the session and clear undo; they refuse while there are unsaved changes unless discard=true. Paths are relative to the server's working directory; saving outside it is refused unless the server was started with --allow-any-path.".into(),
            schema: obj(json!({
                "action": {"type": "string", "enum": ["save", "open", "new"], "description": "What to do"},
                "path": {"type": "string", "description": "Project file (.json). Required to open; optional to save"},
                "discard": {"type": "boolean", "description": "Open or start anew even though unsaved changes will be lost"}
            }), &["action"]),
            effect: Effect::Destroys,
            run: Run::Call(Tools::project_file),
        },
    ]
}

impl Tools {
    fn transport(&mut self, a: &Map<String, Value>) -> Outcome {
        let meter = self.meter()?;
        let mut args = a.clone();
        for key in ["position", "loop_start", "loop_end"] {
            if let Some(v) = a.get(key) {
                args.insert(key.into(), json!(music::position(v, meter, key)?));
            }
        }
        let r = self.lua("transport", Value::Object(args))?;
        let out = format!("Transport: {}\n", format::transport(&r["transport"], meter));
        Ok(Self::reply(out, &r, meter))
    }

    fn undo(&mut self, a: &Map<String, Value>) -> Outcome {
        let r = self.lua("undo", Value::Object(a.clone()))?;
        let meter = Meter::default();
        if a.get("list") == Some(&json!(true)) {
            let mut out = String::new();
            let history = items(&r["history"]);
            if history.is_empty() {
                out.push_str("Nothing to undo: the history is empty.\n");
            } else {
                out.push_str("History, newest first (undo takes the first):\n");
                for h in history {
                    let _ = writeln!(out, "  {}", h["label"].as_str().unwrap_or(""));
                }
            }
            let redo = items(&r["redoable"]);
            if !redo.is_empty() {
                out.push_str("Redo would bring back, next first:\n");
                for h in redo {
                    let _ = writeln!(out, "  {}", h["label"].as_str().unwrap_or(""));
                }
            }
            return Ok(Self::reply(out, &r, meter));
        }
        let redo = a.get("redo") == Some(&json!(true));
        let steps = a.get("steps").and_then(Value::as_u64).unwrap_or(1);
        let done = r["done"].as_u64().unwrap_or(0);
        let (word, noun) = if redo { ("Redid", "redo") } else { ("Undid", "undo") };
        if done == 0 {
            return err(format!("Nothing to {noun}."));
        }
        let labels: Vec<&str> = items(&r["steps"]).iter().filter_map(Value::as_str).collect();
        let mut out = format!(
            "{word} {done} step{}: {}.\n",
            if done == 1 { "" } else { "s" },
            labels.join("; ")
        );
        if done < steps {
            let _ = writeln!(out, "(That was all there was to {noun}: you asked for {steps}.)");
        }
        out.push_str("get_project shows the project now.\n");
        Ok(Self::reply(out, &r, meter))
    }

    fn project_file(&mut self, a: &Map<String, Value>) -> Outcome {
        let action = a["action"].as_str().unwrap_or("");
        let mut args = json!({ "action": action, "discard": a.get("discard") });
        match action {
            "save" => {
                let path = match a.get("path").and_then(Value::as_str) {
                    Some(path) => self.output_path(path)?,
                    None => {
                        let p = self.kernel.call("project_get", json!([]))?;
                        match p["path"].as_str() {
                            Some(path) => self.write_path(path)?,
                            None => {
                                return err(
                                    "the project has never been saved: give a `path`, such as \"song.json\"",
                                );
                            }
                        }
                    }
                };
                args["path"] = json!(path);
            }
            "open" => {
                let path = a
                    .get("path")
                    .and_then(Value::as_str)
                    .ok_or_else(|| ToolError("open needs a `path`".into()))?;
                let path = self.read_path(path);
                if !path.is_file() {
                    return err(format!("no project file at {}", path.display()));
                }
                args["action"] = json!("load");
                args["path"] = json!(path);
            }
            _ => {}
        }
        let r = self.lua("file", args)?;
        let (out, meter) = match r["saved"].as_str() {
            Some(path) => (format!("Saved to {path}.\n"), Meter::default()),
            None => (
                format!(
                    "{}\n{}",
                    if action == "new" {
                        "Started a new project."
                    } else {
                        "Opened."
                    },
                    format::project(&r["project"])
                ),
                Meter::from_project(&r["project"]),
            ),
        };
        Ok(Self::reply(out, &r, meter))
    }
}
