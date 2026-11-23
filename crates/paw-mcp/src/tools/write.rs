//! The tools that change the project. Each is one undo step, alone or as a
//! step of a `batch`.

use std::fmt::Write as _;

use serde_json::{Map, Value, json};

use super::{Args, Effect, Outcome, Reply, Run, Tool, ToolError, Tools, as_map, err, find, items};
use crate::check::validate;
use crate::format;
use crate::music::{self, Meter};
use crate::schema::*;

pub(super) fn tools() -> Vec<Tool> {
    vec![
        Tool {
            name: "add_part",
            title: "Add a part",
            description: format!(
                "Add a part, and in the same call its devices (instrument first, then effects), clips with their notes, routing and sends. A MIDI part needs an instrument device such as `synth` or `drums` to make sound. Returns the new part with every id. {UNDO}"
            ),
            schema: obj(
                json!({
                    "name": {"type": "string", "description": "Part name"},
                    "volume": {"type": "number", "description": "Fader in dB, -120 to 24 (default 0)"},
                    "pan": {"type": "number", "description": "-1 left to 1 right (default 0)"},
                    "output": part_ref("Route the part's output into this part instead of the master (for buses)"),
                    "index": {"type": "integer", "minimum": 1, "description": "Position in the part list, from 1 (default last)"},
                    "color": {"type": "string", "description": "Colour as #rrggbb"},
                    "devices": {"type": "array", "items": device_spec(), "description": "Devices to add in chain order"},
                    "clips": {"type": "array", "items": clip_spec(), "description": "Clips to add"},
                    "sends": send_spec("Sends to other parts (for shared reverbs and the like)")
                }),
                &[],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: Some(Tools::prepare_add_part), show: show_add_part },
        },
        Tool {
            name: "set_part",
            title: "Change a part",
            description: format!(
                "Change a part's name, volume, pan, mute, solo, colour, position, output routing or sends. Only what is given changes. `sends` replaces the whole list (pass [] to remove all). Returns the part as it is afterwards. {UNDO}"
            ),
            schema: obj(
                json!({
                    "part": part_ref("The part"),
                    "name": {"type": "string", "description": "New name"},
                    "volume": {"type": "number", "description": "Fader in dB, -120 to 24"},
                    "pan": {"type": "number", "description": "-1 left to 1 right"},
                    "mute": {"type": "boolean", "description": "Mute"},
                    "solo": {"type": "boolean", "description": "Solo"},
                    "color": {"type": "string", "description": "Colour as #rrggbb"},
                    "index": {"type": "integer", "minimum": 1, "description": "Move to this position in the part list, from 1"},
                    "output": part_ref("Route into this part; \"master\" for the master"),
                    "sends": send_spec("The complete list of sends")
                }),
                &["part"],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: None, show: show_set_part },
        },
        Tool {
            name: "add_clip",
            title: "Add a clip with notes",
            description: format!(
                "Add a MIDI clip with all its notes in one call, or an audio clip from a file. Returns the clip's id and its notes. To change notes later use edit_clip. {UNDO}"
            ),
            schema: {
                let mut schema = clip_spec();
                schema["properties"]["part"] = part_ref("The part to put it on");
                schema["required"] = json!(["part"]);
                schema
            },
            effect: Effect::Changes,
            run: Run::Write { prepare: Some(Tools::prepare_add_clip), show: show_add_clip },
        },
        Tool {
            name: "edit_clip",
            title: "Change a clip or its notes",
            description: format!(
                "Change a clip: move it (start, or another part), resize, rename, mute; and edit its notes. Notes are named by the ids get_clip shows: remove some (`remove_notes`, by ids and/or pitch and/or time range, or all), change single notes (`edit_notes`: new pitch, start, length or velocity by id), transpose (semitones, or `degrees` along the project's key so that a third up stays in key), scale velocities (`velocity` multiplies) or set them (`set_velocity`: an absolute value, over all notes or a pitch/time range), replace all notes (`notes`) or add more (`add_notes`). Applied in that order. Note positions are relative to the clip's start. Returns the clip with its notes. {UNDO}"
            ),
            schema: obj(
                json!({
                    "clip": {"type": "integer", "description": "Clip id"},
                    "name": {"type": "string", "description": "New name"},
                    "start": position("New start on the timeline"),
                    "length": length("New length"),
                    "muted": {"type": "boolean", "description": "Mute the clip"},
                    "part": part_ref("Move the clip to this part"),
                    "gain": {"type": "number", "description": "Audio clips: gain in dB"},
                    "remove_notes": {
                        "type": "object",
                        "description": "Remove notes matching all that is given: ids, pitches, and a range of starts [from, to) within the clip",
                        "properties": {
                            "all": {"type": "boolean", "description": "Remove every note"},
                            "ids": {"type": "array", "items": {"type": "integer"}, "description": "Only these notes, by id"},
                            "pitches": pitches("Only these pitches (\"C4\", 60)"),
                            "from": position("Only notes starting at or after this point in the clip"),
                            "to": position("Only notes starting before this point in the clip")
                        },
                        "additionalProperties": false
                    },
                    "edit_notes": {
                        "type": "array",
                        "description": "Change single notes, each named by its id; only what is given changes",
                        "items": {
                            "type": "object",
                            "description": "One note's changes",
                            "properties": {
                                "id": {"type": "integer", "description": "The note's id (from get_clip)"},
                                "pitch": pitch("New pitch"),
                                "start": position("New start, from the clip's start"),
                                "length": length("New length"),
                                "velocity": {"type": "integer", "minimum": 1, "maximum": 127, "description": "New velocity"}
                            },
                            "required": ["id"],
                            "additionalProperties": false
                        }
                    },
                    "transpose": {
                        "anyOf": [
                            {"type": "integer"},
                            {
                                "type": "object",
                                "description": "Transpose in semitones and/or scale degrees",
                                "properties": {
                                    "semitones": {"type": "integer", "description": "Semitones to move every remaining note by"},
                                    "degrees": {"type": "integer", "description": "Scale degrees to move by, in the key: 2 is a third up, -4 a fifth down; notes outside the key keep their distance from the scale note below them"},
                                    "key": {"type": "string", "description": "The key for `degrees`, such as \"D minor\" (default the project's key, else the key paw reads from the music at each note)"}
                                },
                                "additionalProperties": false
                            }
                        ],
                        "description": "Semitones (an integer) to move every remaining note by, or an object for scale degrees in the key: {\"degrees\": 2}"
                    },
                    "velocity": {"type": "number", "exclusiveMinimum": 0, "description": "Multiply every remaining note's velocity by this (0.5 halves it)"},
                    "set_velocity": {
                        "type": "object",
                        "description": "Set velocities to one value, for all notes or those in a pitch and time range",
                        "properties": {
                            "value": {"type": "integer", "minimum": 1, "maximum": 127, "description": "The velocity"},
                            "pitches": pitches("Only these pitches"),
                            "from": position("Only notes starting at or after this point in the clip"),
                            "to": position("Only notes starting before this point in the clip")
                        },
                        "required": ["value"],
                        "additionalProperties": false
                    },
                    "notes": notes_schema("Replace all the clip's notes with these"),
                    "add_notes": notes_schema("Notes to add to the clip")
                }),
                &["clip"],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: Some(Tools::prepare_edit_clip), show: show_edit_clip },
        },
        Tool {
            name: "duplicate_clip",
            title: "Copy a clip",
            description: format!(
                "Copy a clip, with its notes and settings: right after the original by default, or at `at`, on another `part`, `times` times in a row. Returns the copies. {UNDO}"
            ),
            schema: obj(
                json!({
                    "clip": {"type": "integer", "description": "Clip id"},
                    "at": position("Where the first copy starts (default right after the original)"),
                    "part": part_ref("Put the copies on this part (default the same)"),
                    "times": {"type": "integer", "minimum": 1, "maximum": 64, "description": "How many copies, one after another (default 1)"},
                    "gap": {"type": "number", "minimum": 0, "description": "Beats of space between copies (default none)"}
                }),
                &["clip"],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: Some(Tools::prepare_duplicate_clip), show: show_copies },
        },
        Tool {
            name: "repeat_bars",
            title: "Repeat a stretch of the song",
            description: format!(
                "Copy every clip that lies wholly between two points (all parts, or `parts`) to later in the song, `times` times in a row, for arranging: repeat bars 1 to 8 as 9 to 16. A clip that crosses a boundary is skipped and named in the result. {UNDO}"
            ),
            schema: obj(
                json!({
                    "from": position("Start of the stretch"),
                    "to": position("End of the stretch (the first point after it)"),
                    "at": position("Where the first copy of the stretch starts (default right after it)"),
                    "times": {"type": "integer", "minimum": 1, "maximum": 64, "description": "How many repeats, one after another (default 1)"},
                    "parts": {"type": "array", "items": part_ref("A part"), "description": "Only the clips of these parts (default all)"}
                }),
                &["from", "to"],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: Some(Tools::prepare_repeat_bars), show: show_copies },
        },
        Tool {
            name: "add_device",
            title: "Add a device or plugin",
            description: format!(
                "Add an instrument or effect to the end of a part's chain (or at `index`), optionally with parameter values. `kind` is an exact kind or words to search (find_devices shows what there is). Returns the device's id and all its parameters with ranges. {UNDO}"
            ),
            schema: obj(
                json!({
                    "part": part_ref("The part"),
                    "kind": {"type": "string", "description": "Device kind (\"synth\", \"drums\", \"gain\", \"delay\", \"clap:...\") or words to search for"},
                    "params": params_schema("Parameter values by key or name; a switch-like parameter also takes its choice's name (\"wave\": \"saw\")"),
                    "index": {"type": "integer", "minimum": 1, "description": "Position in the chain, from 1 (default last)"},
                    "bypass": {"type": "boolean", "description": "Add it bypassed"}
                }),
                &["part", "kind"],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: None, show: show_add_device },
        },
        Tool {
            name: "set_device",
            title: "Change a device",
            description: format!(
                "Set a device's parameters, bypass it, or move it in its chain or to another part. Values outside a parameter's range are clamped; the result shows the values as they are now. {UNDO}"
            ),
            schema: obj(
                json!({
                    "device": {"type": "integer", "description": "Device id"},
                    "params": params_schema("Parameter values by key or name, e.g. {\"cutoff\": 1200, \"resonance\": 0.4, \"wave\": \"square\"}"),
                    "bypass": {"type": "boolean", "description": "Bypass (true) or enable (false)"},
                    "part": part_ref("Move the device to this part"),
                    "index": {"type": "integer", "minimum": 1, "description": "Move to this position in the chain, from 1"}
                }),
                &["device"],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: None, show: show_set_device },
        },
        Tool {
            name: "automate",
            title: "Automate volume, pan or a parameter",
            description: format!(
                "Write automation: a part's volume (dB) or pan (-1..1), or a device parameter (give `device` and `param`), as points joined by straight lines and held before the first and after the last. Creates the lane if needed. By default the points replace the lane's; mode \"add\" merges them (a point replaces one at the same beat). Two points at one beat make a step. Can also turn a lane off or remove it. While playing or rendering an enabled lane overrides the fader or parameter. {UNDO}"
            ),
            schema: obj(
                json!({
                    "part": part_ref("The part (for volume or pan; optional with `device`)"),
                    "target": {"type": "string", "enum": ["volume", "pan"], "description": "What to automate on the part (default volume); ignored when `device` is given"},
                    "device": {"type": "integer", "description": "Automate a parameter of this device instead"},
                    "param": {"type": "string", "description": "The device parameter's key or name"},
                    "points": {
                        "type": "array",
                        "description": "Points as [position, value] pairs: the position in beats (a number) or \"bar.beat\" (a string), then the value (a number) in the target's units, e.g. [[0, -40], [\"5.1\", 0]]",
                        "items": {
                            "type": "array",
                            "description": "One point: [position, value]",
                            "minItems": 2,
                            "maxItems": 2,
                            "items": {
                                "anyOf": [{"type": "number"}, {"type": "string"}],
                                "description": "First the position (beats or \"bar.beat\"), then the value (a number)"
                            }
                        }
                    },
                    "mode": {"type": "string", "enum": ["replace", "add"], "description": "Replace the lane's points (default) or add to them"},
                    "clear": {"type": "boolean", "description": "Remove every point first"},
                    "enabled": {"type": "boolean", "description": "Turn the lane on or off (off keeps its points but stops moving the target)"},
                    "remove": {"type": "boolean", "description": "Remove the lane altogether"}
                }),
                &[],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: Some(Tools::prepare_automate), show: show_automate },
        },
        Tool {
            name: "set_project",
            title: "Tempo, signature, key, name",
            description: format!(
                "Set the project's tempo (BPM, 1 to 999) and time signature (\"3/4\", \"6/8\") at the start, the changes along the song, its key (\"D minor\", used by diatonic transpose and shown by get_project; \"\" clears it) or its name. `tempo_changes` and `signature_changes` replace every change after the start; a tempo change with `ramp` moves linearly (in time) to the next change's tempo; a signature change starts a new bar where it is. Audio clips keep their length in seconds when the tempo changes. {UNDO}"
            ),
            schema: obj(
                json!({
                    "tempo": {"type": "number", "minimum": 1, "maximum": 999, "description": "Beats per minute"},
                    "signature": {"type": "string", "description": "Time signature such as \"4/4\", \"3/4\", \"6/8\""},
                    "key": {"type": "string", "description": "The key, such as \"D minor\", \"F# dorian\", \"Bb\"; an empty text clears it"},
                    "name": {"type": "string", "description": "Project name"},
                    "tempo_changes": {"type": "array", "description": "Tempo changes after the start, replacing those there are: [{\"at\": \"9.1\" or beats, \"bpm\": 90, \"ramp\": false}]; [] for one tempo throughout", "items": {"type": "object", "description": "A tempo change", "properties": {"at": position("Where"), "bpm": {"type": "number", "description": "Beats per minute from there on"}, "ramp": {"type": "boolean", "description": "Move linearly to the next change's tempo"}}, "required": ["at", "bpm"]}},
                    "signature_changes": {"type": "array", "description": "Time signature changes after the start, replacing those there are: [{\"at\": \"9\" or beats, \"signature\": \"6/8\"}]", "items": {"type": "object", "description": "A signature change", "properties": {"at": position("Where the new bar starts"), "signature": {"type": "string", "description": "Such as \"6/8\""}}, "required": ["at", "signature"]}}
                }),
                &[],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: Some(Tools::prepare_set_project), show: show_set_project },
        },
        Tool {
            name: "marker",
            title: "Markers and regions",
            description: format!(
                "Name places and stretches of the song: add a marker at a position (with `length` it is a region, a named stretch), rename, move (and resize) or remove one, or list them all. Regions can be rendered (`render` with `region`) and looped (`transport` with `loop_marker`). Markers move with the beats when the tempo changes. {UNDO}"
            ),
            schema: obj(
                json!({
                    "action": {"type": "string", "enum": ["add", "rename", "move", "remove", "list"], "description": "What to do"},
                    "marker": marker_ref("The marker or region (rename, move, remove)"),
                    "name": {"type": "string", "description": "Its name (add, rename)"},
                    "at": position("Where it is (add), or where it moves to (move)"),
                    "length": length("Makes it a region of this length (add), or resizes one (move)"),
                    "color": {"type": "string", "description": "Colour as #rrggbb (add)"}
                }),
                &["action"],
            ),
            effect: Effect::Changes,
            run: Run::Write { prepare: Some(Tools::prepare_marker), show: show_marker },
        },
        Tool {
            name: "remove",
            title: "Remove parts, clips, devices, lanes",
            description: format!(
                "Remove any number of parts, clips, devices, automation lanes and markers in one call. Removing a part removes its clips and devices; parts routed into it fall back to the master. {UNDO}"
            ),
            schema: obj(
                json!({
                    "parts": {"type": "array", "items": part_ref("A part"), "description": "Parts, by id or name"},
                    "clips": {"type": "array", "items": {"type": "integer"}, "description": "Clip ids"},
                    "devices": {"type": "array", "items": {"type": "integer"}, "description": "Device ids"},
                    "automation": {"type": "array", "items": {"type": "integer"}, "description": "Automation lane ids"},
                    "markers": {"type": "array", "items": marker_ref("A marker or region"), "description": "Markers and regions, by id or name"}
                }),
                &[],
            ),
            effect: Effect::Destroys,
            run: Run::Write { prepare: Some(Tools::prepare_remove), show: show_remove },
        },
        Tool {
            name: "batch",
            title: "Several changes as one undo step",
            description: format!(
                "Run several of the writing tools (add_part, set_part, add_clip, edit_clip, duplicate_clip, repeat_bars, add_device, set_device, automate, set_project, marker, remove) in order as ONE undo step, named `mcp: <label>`: if any step fails, none of them is kept. A later step may name what an earlier one made by name (a part by its name), not by id, since ids are only known afterwards; positions in `bar.beat` are read with the time signature as it is when the batch starts. Returns every step's result. {UNDO}"
            ),
            schema: obj(
                json!({
                    "label": {"type": "string", "description": "What the batch does, shown by undo's history (\"verse drums\")"},
                    "steps": {
                        "type": "array",
                        "minItems": 1,
                        "maxItems": 100,
                        "description": "The steps, in order",
                        "items": {
                            "type": "object",
                            "description": "One step: a writing tool and its arguments",
                            "properties": {
                                "tool": {"type": "string", "enum": BATCHABLE, "description": "The tool"},
                                "arguments": {"type": "object", "description": "Its arguments, as when it is called alone"}
                            },
                            "required": ["tool", "arguments"],
                            "additionalProperties": false
                        }
                    }
                }),
                &["steps"],
            ),
            effect: Effect::Destroys,
            run: Run::Call(Tools::batch),
        },
    ]
}

/// Put `keys` of `a`, read as positions, into `args` in beats.
fn positions(a: &Args, args: &mut Args, meter: &Meter, keys: &[&str]) -> Result<(), ToolError> {
    for key in keys {
        if let Some(v) = a.get(*key) {
            args.insert((*key).into(), json!(music::position(v, meter, key)?));
        }
    }
    Ok(())
}

/// Put `a`'s `length`, read as a length, into `args` in beats.
fn length_in_beats(a: &Args, args: &mut Args, meter: &Meter) -> Result<(), ToolError> {
    if let Some(length) = a.get("length") {
        args.insert("length".into(), json!(music::length(length, meter, "length")?));
    }
    Ok(())
}

// Each `prepare_*` gives a tool's arguments in the kernel's units: positions
// and lengths in beats, pitches as numbers, paths made absolute.
impl Tools {
    fn clip_args(&self, c: &Args, meter: &Meter) -> Result<Args, ToolError> {
        let mut out = Map::new();
        if let Some(name) = c.get("name") {
            out.insert("name".into(), name.clone());
        }
        positions(c, &mut out, meter, &["start"])?;
        length_in_beats(c, &mut out, meter)?;
        if let Some(notes) = c.get("notes") {
            out.insert("notes".into(), json!(music::notes(notes, meter)?));
        }
        if let Some(file) = c.get("file").and_then(Value::as_str) {
            let path = self.read_path(file);
            if !path.is_file() {
                return err(format!("no audio file at {}", path.display()));
            }
            if c.contains_key("notes") {
                return err("a clip has notes or a file, not both");
            }
            out.insert("file".into(), json!(path));
        }
        Ok(out)
    }

    fn prepare_add_part(&self, a: &Args, meter: &Meter) -> Result<Args, ToolError> {
        let mut args = a.clone();
        if let Some(clips) = a.get("clips") {
            let mut list = Vec::new();
            for (i, c) in items(clips).iter().enumerate() {
                let c = c
                    .as_object()
                    .ok_or_else(|| ToolError("each clip is an object".into()))?;
                let clip = self
                    .clip_args(c, meter)
                    .map_err(|e| ToolError(format!("clip {}: {}", i + 1, e.0)))?;
                list.push(Value::Object(clip));
            }
            args.insert("clips".into(), Value::Array(list));
        }
        Ok(args)
    }

    fn prepare_add_clip(&self, a: &Args, meter: &Meter) -> Result<Args, ToolError> {
        let mut clip = self.clip_args(a, meter)?;
        clip.insert("part".into(), a["part"].clone());
        Ok(clip)
    }

    fn prepare_edit_clip(&self, a: &Args, meter: &Meter) -> Result<Args, ToolError> {
        let mut args = a.clone();
        positions(a, &mut args, meter, &["start"])?;
        length_in_beats(a, &mut args, meter)?;
        for key in ["notes", "add_notes"] {
            if let Some(notes) = a.get(key) {
                args.insert(key.into(), json!(music::notes(notes, meter)?));
            }
        }
        for key in ["remove_notes", "set_velocity"] {
            if let Some(Value::Object(r)) = a.get(key) {
                let mut out = r.clone();
                if let Some(p) = r.get("pitches") {
                    out.insert("pitches".into(), json!(music::pitches(p)?));
                }
                positions(r, &mut out, meter, &["from", "to"])?;
                let selective = ["all", "ids", "pitches", "from", "to"]
                    .iter()
                    .any(|k| out.contains_key(*k));
                if key == "remove_notes" && !selective {
                    return err("remove_notes needs `all`, `ids`, `pitches`, `from` or `to`");
                }
                args.insert(key.into(), Value::Object(out));
            }
        }
        if let Some(Value::Array(list)) = a.get("edit_notes") {
            let mut out = Vec::new();
            for (i, e) in list.iter().enumerate() {
                let mut e = as_map(e);
                let note = |e: &mut Args| -> Result<(), anyhow::Error> {
                    if let Some(p) = e.get("pitch").cloned() {
                        let all = music::pitches(&p)?;
                        anyhow::ensure!(all.len() == 1, "a note has one pitch, not a chord");
                        e.insert("pitch".into(), json!(all[0]));
                    }
                    if let Some(v) = e.get("start").cloned() {
                        e.insert("start".into(), json!(music::note_start(&v, meter)?));
                    }
                    if let Some(v) = e.get("length").cloned() {
                        e.insert("length".into(), json!(music::length(&v, meter, "length")?));
                    }
                    Ok(())
                };
                note(&mut e).map_err(|x| ToolError(format!("edit_notes[{i}]: {x:#}")))?;
                out.push(Value::Object(e));
            }
            args.insert("edit_notes".into(), Value::Array(out));
        }
        Ok(args)
    }

    fn prepare_duplicate_clip(&self, a: &Args, meter: &Meter) -> Result<Args, ToolError> {
        let mut args = a.clone();
        positions(a, &mut args, meter, &["at"])?;
        Ok(args)
    }

    fn prepare_repeat_bars(&self, a: &Args, meter: &Meter) -> Result<Args, ToolError> {
        let mut args = a.clone();
        positions(a, &mut args, meter, &["from", "to", "at"])?;
        Ok(args)
    }

    fn prepare_automate(&self, a: &Args, meter: &Meter) -> Result<Args, ToolError> {
        let mut args = a.clone();
        if let Some(points) = a.get("points") {
            let mut list = Vec::new();
            for (i, p) in items(points).iter().enumerate() {
                let pair = items(p);
                if pair.len() != 2 {
                    return err(format!("point {}: write it as [position, value]", i + 1));
                }
                let beat = music::position(&pair[0], meter, "position")
                    .map_err(|e| ToolError(format!("point {}: {e:#}", i + 1)))?;
                let value = pair[1].as_f64().ok_or_else(|| {
                    ToolError(format!("point {}: the value must be a number", i + 1))
                })?;
                list.push(json!([beat, value]));
            }
            args.insert("points".into(), Value::Array(list));
        }
        if a.contains_key("device") && !a.contains_key("param") && a.get("remove") != Some(&json!(true))
        {
            return err(
                "automating a device needs `param`, the parameter's key or name (get_device lists them)",
            );
        }
        Ok(args)
    }

    fn prepare_set_project(&self, a: &Args, meter: &Meter) -> Result<Args, ToolError> {
        let mut args = a.clone();
        if let Some(sig) = a.get("signature").and_then(Value::as_str) {
            let (n, d) = music::signature(sig)?;
            args.remove("signature");
            args.insert("sig_num".into(), json!(n));
            args.insert("sig_den".into(), json!(d));
        }
        if let Some(list) = a.get("tempo_changes").and_then(Value::as_array) {
            let mut out = Vec::new();
            for c in list {
                let at = music::position(&c["at"], meter, "tempo change position")?;
                let ramp = c["ramp"].as_bool().unwrap_or(false);
                out.push(json!({"beat": at, "bpm": c["bpm"], "ramp": ramp}));
            }
            args.insert("tempo_changes".into(), Value::Array(out));
        }
        if let Some(list) = a.get("signature_changes").and_then(Value::as_array) {
            let mut out = Vec::new();
            for c in list {
                let at = music::position(&c["at"], meter, "signature change position")?;
                let (n, d) = music::signature(c["signature"].as_str().unwrap_or(""))?;
                out.push(json!({"beat": at, "num": n, "den": d}));
            }
            args.insert("signature_changes".into(), Value::Array(out));
        }
        Ok(args)
    }

    fn prepare_marker(&self, a: &Args, meter: &Meter) -> Result<Args, ToolError> {
        let mut args = a.clone();
        positions(a, &mut args, meter, &["at"])?;
        length_in_beats(a, &mut args, meter)?;
        Ok(args)
    }

    fn prepare_remove(&self, a: &Args, _meter: &Meter) -> Result<Args, ToolError> {
        if a.values().all(|v| items(v).is_empty()) {
            return err("nothing to remove: give parts, clips, devices, automation or markers");
        }
        Ok(a.clone())
    }

    /// Several writing tools as one undo step.
    fn batch(&mut self, a: &Args) -> Outcome {
        let meter = self.meter()?;
        let steps = items(&a["steps"]);
        let mut ops = Vec::new();
        let mut tools = Vec::new();
        for (i, step) in steps.iter().enumerate() {
            let at = |e: ToolError| ToolError(format!("step {}: {}", i + 1, e.0));
            let name = step["tool"].as_str().unwrap_or("");
            let tool = find(name).filter(|t| t.is_write()).ok_or_else(|| {
                ToolError(format!(
                    "step {}: `{name}` is not a tool a batch can run; they are {}",
                    i + 1,
                    BATCHABLE.join(", ")
                ))
            })?;
            let args = as_map(&step["arguments"]);
            validate(&tool.schema, &args).map_err(at)?;
            let prepared = self.prepare(tool, &args, &meter).map_err(at)?;
            ops.push(json!({ "tool": name, "args": prepared }));
            tools.push(tool);
        }
        let label = match a.get("label").and_then(Value::as_str) {
            Some(label) => format!("mcp: {label}"),
            None => format!("mcp: batch of {} steps", ops.len()),
        };
        let r = self.lua_as("batch", json!({ "ops": ops }), Some(&label))?;
        let mut out = format!("Did {} steps as one undo step ({label}):\n", tools.len());
        let mut data = Vec::new();
        for (i, (tool, result)) in tools.iter().zip(items(&r["results"])).enumerate() {
            let shown = Self::show(tool, result, &meter);
            let _ = write!(
                out,
                "{}. {}: {}",
                i + 1,
                tool.name,
                shown.text.trim_start_matches(['\n', ' '])
            );
            data.push(json!({ "tool": tool.name, "result": shown.data }));
        }
        format::messages(&mut out, &r["messages"]);
        Ok(Reply {
            text: out,
            data: json!({
                "label": label, "results": data, "edited": r["edited"], "messages": r["messages"],
            }),
        })
    }
}

// Each `show_*` gives a writing tool's answer as text.

fn show_add_part(r: &Value, meter: &Meter) -> String {
    let mut out = String::from("Added part:\n");
    format::part(&mut out, &r["part"], meter, false);
    out
}

fn show_set_part(r: &Value, meter: &Meter) -> String {
    let mut out = String::from("Part now:\n");
    format::part(&mut out, &r["part"], meter, false);
    out
}

fn show_add_clip(r: &Value, meter: &Meter) -> String {
    let mut out = String::from("Added clip ");
    format::clip(&mut out, &r["clip"], meter);
    out
}

fn show_edit_clip(r: &Value, meter: &Meter) -> String {
    let c = &r["clip"];
    let mut out = String::from("Clip now: ");
    format::clip(&mut out, c, meter);
    if let Some(n) = c["removed_notes"].as_u64().filter(|n| *n > 0) {
        let _ = writeln!(out, "({n} note{} removed)", if n == 1 { "" } else { "s" });
    }
    if let Some(n) = c["changed_notes"].as_u64().filter(|n| *n > 0) {
        let _ = writeln!(out, "({n} note{} changed)", if n == 1 { "" } else { "s" });
    }
    let keys: Vec<&str> = items(&c["keys_used"]).iter().filter_map(Value::as_str).collect();
    if !keys.is_empty() {
        let _ = writeln!(out, "(scale degrees counted in {})", keys.join(", "));
    }
    if c["notes"].is_null() && c["kind"] == "midi" {
        out.push_str("(more than 64 notes: get_clip lists them)\n");
    }
    out
}

/// The answer of `duplicate_clip` and `repeat_bars`: the copies.
fn show_copies(r: &Value, meter: &Meter) -> String {
    let mut out = String::new();
    let clips = items(&r["clips"]);
    let _ = writeln!(
        out,
        "Made {} cop{}:",
        clips.len(),
        if clips.len() == 1 { "y" } else { "ies" }
    );
    for c in clips {
        let _ = writeln!(out, "  {}", format::clip_line(c, meter));
    }
    let skipped = items(&r["skipped"]);
    if !skipped.is_empty() {
        let list: Vec<String> = skipped.iter().map(Value::to_string).collect();
        let _ = writeln!(
            out,
            "Skipped clips that cross the stretch's edge: {}",
            list.join(", ")
        );
    }
    out
}

fn show_add_device(r: &Value, _meter: &Meter) -> String {
    let mut out = String::from("Added device:\n");
    format::device(&mut out, &r["device"], "", 48);
    out
}

fn show_set_device(r: &Value, _meter: &Meter) -> String {
    let mut out = String::from("Device now:\n");
    format::device(&mut out, &r["device"], "", 48);
    out
}

/// The names in `r[key]`, joined.
fn joined(r: &Value, key: &str) -> String {
    items(&r[key])
        .iter()
        .filter_map(Value::as_str)
        .collect::<Vec<_>>()
        .join(", ")
}

fn show_automate(r: &Value, meter: &Meter) -> String {
    let mut out = String::new();
    if r["removed"].is_array() {
        let _ = writeln!(out, "Removed {}", joined(r, "removed"));
    } else {
        let l = &r["lane"];
        let _ = writeln!(
            out,
            "{} automation on part \"{}\" [id {}]{}:\n  {}",
            if l["created"].as_bool() == Some(true) {
                "New"
            } else {
                "Updated"
            },
            l["part_name"].as_str().unwrap_or(""),
            l["part"],
            l["device_name"]
                .as_str()
                .map(|n| format!(", device {n}"))
                .unwrap_or_default(),
            format::lane(l, meter)
        );
    }
    out
}

fn show_set_project(r: &Value, _meter: &Meter) -> String {
    let p = &r["project"];
    let mut out = format::project_header(p, &Meter::from_project(p));
    out.push('\n');
    out
}

fn show_marker(r: &Value, meter: &Meter) -> String {
    let mut out = String::new();
    if r["removed"].is_array() {
        let _ = writeln!(out, "Removed {}.", joined(r, "removed"));
    } else if r["marker"].is_object() {
        let _ = writeln!(out, "Marker: {}", format::marker_line(&r["marker"], meter));
    }
    let all = items(&r["markers"]);
    if all.is_empty() {
        out.push_str("There are no markers or regions.\n");
    } else {
        let _ = writeln!(out, "Markers and regions ({}):", all.len());
        for m in all {
            let _ = writeln!(out, "  {}", format::marker_line(m, meter));
        }
    }
    out
}

fn show_remove(r: &Value, _meter: &Meter) -> String {
    format!("Removed {}.\n", joined(r, "removed"))
}
