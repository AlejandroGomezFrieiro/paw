//! What a model sees of each tool: its name, description and input schema.
//!
//! The schemas stay in the plain subset every client reads: `anyOf` for a
//! value that may be of two kinds (never a list of types, which some clients
//! read as the first only), arrays with one `items` schema (never
//! `prefixItems`), and a description on every property.

use std::sync::LazyLock;

use serde_json::{Map, Value, json};

/// The kernel's schema of the data of `paw.api`, by the name of each type
/// (`ClipChanges`), from the Rust types that read the data.
/// tools/apidoc.lua writes the file from `paw.api.api_schema`, and its
/// check fails when the file is not that schema.
static API: LazyLock<Map<String, Value>> = LazyLock::new(|| {
    serde_json::from_str(include_str!("api_schema.json")).expect("api_schema.json is the JSON that apidoc writes")
});

/// The schema of the field `key` of the kernel's type `of` (a setter's
/// changes, such as `ClipChanges`), in the plain subset, with
/// `description` for the model. A field that the type does not have is a
/// fault of the server, which its tests find.
pub(crate) fn api_field(of: &str, key: &str, description: &str) -> Value {
    let field = API
        .get(of)
        .and_then(|def| def.pointer(&format!("/properties/{key}")))
        .unwrap_or_else(|| panic!("the kernel's `{of}` has no field `{key}`"));
    let mut field = plain(field);
    field["description"] = description.into();
    field
}

/// A schema of the kernel in the plain subset: a definition in place of its
/// `$ref`, the type alone where the kernel also takes nil (a model leaves
/// the field out), and no words that are only for paw (`x-teal`, the Rust
/// `format` of a number).
fn plain(schema: &Value) -> Value {
    if let Some(name) = schema.get("$ref").and_then(Value::as_str).and_then(|r| r.strip_prefix("#/$defs/")) {
        return plain(&API[name]);
    }
    if let Some(choices) = schema.get("anyOf").and_then(Value::as_array) {
        let kept: Vec<&Value> = choices.iter().filter(|c| c.get("type") != Some(&json!("null"))).collect();
        if let [one] = kept[..] {
            return plain(one);
        }
    }
    let mut out = schema.clone();
    if let Some(map) = out.as_object_mut() {
        for word in ["x-teal", "format", "default", "description"] {
            map.remove(word);
        }
        if let Some(kinds) = map.get("type").and_then(Value::as_array) {
            let kind = kinds.iter().find(|k| k.as_str() != Some("null")).cloned().unwrap_or_default();
            map.insert("type".into(), kind);
        }
    }
    out
}

/// Tools that change the project: each is one undo step, and any of them may
/// be a step of a `batch`.
pub(crate) const BATCHABLE: [&str; 12] = [
    "add_part",
    "set_part",
    "add_clip",
    "edit_clip",
    "add_device",
    "set_device",
    "automate",
    "set_project",
    "marker",
    "duplicate_clip",
    "repeat_bars",
    "remove",
];

pub(crate) const UNDO: &str =
    "Undoable: the whole call is one undo step, and a call that fails changes nothing.";

/// Either of two kinds of value, as `anyOf`.
pub(crate) fn either(first: Value, second: Value, description: String) -> Value {
    json!({ "anyOf": [first, second], "description": description })
}

pub(crate) fn number() -> Value {
    json!({"type": "number"})
}

pub(crate) fn text() -> Value {
    json!({"type": "string"})
}

pub(crate) fn integer() -> Value {
    json!({"type": "integer"})
}

pub(crate) fn part_ref(what: &str) -> Value {
    either(
        integer(),
        text(),
        format!("{what}: its id, its name (any unique part of it, ignoring case), or \"master\""),
    )
}

pub(crate) fn position(what: &str) -> Value {
    either(
        number(),
        text(),
        format!("{what}. A JSON number is beats (quarter notes) from the start, 0 being the start; a string counts bars and beats from 1: \"3.1\" or \"3:1\" or \"bar 3 beat 1\" is the downbeat of bar 3, \"2.3.50\" half a beat after beat 3 of bar 2"),
    )
}

pub(crate) fn length(what: &str) -> Value {
    either(
        number(),
        text(),
        format!("{what}: beats as a number (1 is a quarter note), \"2 bars\", or a note value such as \"1/8\", \"1/16\" or dotted \"1/4.\""),
    )
}

pub(crate) fn marker_ref(what: &str) -> Value {
    either(
        integer(),
        text(),
        format!("{what}: its id, or its name (get_project lists them)"),
    )
}

pub(crate) fn pitch(what: &str) -> Value {
    json!({
        "anyOf": [
            {"type": "string"},
            {"type": "integer", "minimum": 0, "maximum": 127}
        ],
        "description": format!("{what}: a note name (\"C4\", \"F#3\", \"Bb2\", middle C is C4) or a MIDI number"),
    })
}

pub(crate) fn pitches(what: &str) -> Value {
    json!({
        "type": "array",
        "items": pitch("A pitch"),
        "description": what,
    })
}

pub(crate) fn notes_schema(what: &str) -> Value {
    json!({
        "type": "array",
        "description": format!("{what}. Each note is a string \"pitch start [length] [velocity]\" such as \"C4 0 1 100\", \"E4 2.5 1/8\", \"G4 2:1 1/4 90\" or a chord \"C4+E4+G4 2 2\", or an object. In strings the start is beats from the clip's start (\"2.5\"), or bar:beat within the clip with a colon (\"1:3\" = beat 3 of the clip's first bar); in objects a string start is bar.beat (\"1.3\") or bar:beat. Length defaults to 1 beat, velocity to 100. Middle C is C4 (MIDI 60)."),
        "items": {
            "anyOf": [
                {"type": "string", "description": "\"pitch start [length] [velocity]\""},
                {
                    "type": "object",
                    "description": "A note as an object",
                    "properties": {
                        "pitch": {
                            "anyOf": [
                                {"type": "string"},
                                {"type": "integer", "minimum": 0, "maximum": 127},
                                {"type": "array", "items": pitch("A pitch of the chord")}
                            ],
                            "description": "A note name (\"C4\", \"F#3\", \"Bb2\"), a MIDI number 0 to 127, or a chord (\"C4+E4+G4\" or a list of those)"
                        },
                        "start": either(number(), text(), "Beats from the clip's start, or \"bar.beat\" within the clip".into()),
                        "length": either(number(), text(), "Beats, or a note value like \"1/8\". Default 1".into()),
                        "velocity": {"type": "integer", "minimum": 1, "maximum": 127, "description": "1 to 127, default 100"}
                    },
                    "required": ["pitch"],
                    "additionalProperties": false
                }
            ]
        }
    })
}

pub(crate) fn device_spec() -> Value {
    json!({
        "anyOf": [
            {"type": "string", "description": "A device kind or a search such as \"synth\" or \"dragonfly hall\""},
            {
                "type": "object",
                "description": "A device with its settings",
                "properties": {
                    "kind": {"type": "string", "description": "Device kind (\"synth\", \"clap:...\") or words to search for; the first match is used, built-in devices first"},
                    "params": params_schema("Parameter values by key or name, e.g. {\"cutoff\": 800, \"wave\": \"saw\"}"),
                    "bypass": {"type": "boolean", "description": "Start bypassed"}
                },
                "required": ["kind"],
                "additionalProperties": false
            }
        ],
        "description": "A device by kind, or an object with its kind and parameters",
    })
}

pub(crate) fn params_schema(description: &str) -> Value {
    json!({
        "type": "object",
        "description": description,
        "additionalProperties": {
            "anyOf": [{"type": "number"}, {"type": "string"}],
            "description": "A number, or the name of a choice"
        },
    })
}

pub(crate) fn clip_spec() -> Value {
    json!({
        "type": "object",
        "description": "A clip",
        "properties": {
            "name": api_field("ClipChanges", "name", "Clip name"),
            "start": position("Where the clip starts on the timeline"),
            "length": length("Clip length; default whole bars covering the notes"),
            "notes": notes_schema("The clip's notes"),
            "file": api_field("ClipChanges", "file", "An audio file (WAV, AIFF, FLAC, MP3, Ogg) for an audio clip instead of notes"),
        },
        "additionalProperties": false
    })
}

pub(crate) fn send_spec(description: &str) -> Value {
    json!({
        "type": "array",
        "description": description,
        "items": {
            "type": "object",
            "description": "A send",
            "properties": {
                "target": part_ref("Part to send to"),
                "level": {"type": "number", "description": "Send level in dB (default 0)"}
            },
            "required": ["target"],
            "additionalProperties": false
        }
    })
}

pub(crate) fn obj(properties: Value, required: &[&str]) -> Value {
    json!({
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": false,
    })
}

/// The note-range filter of `get_clip`.
pub(crate) fn note_filter() -> Value {
    json!({
        "from": position("Only notes starting at or after this point in the clip"),
        "to": position("Only notes starting before this point in the clip"),
        "pitches": pitches("Only these pitches"),
    })
}

/// Instructions for the model, sent with `initialize`.
pub(crate) const INSTRUCTIONS: &str = "\
This server drives a session of paw (a personal audio workstation). Conventions:
- Ids: parts, devices, clips, notes, markers and automation lanes have numeric ids; get_project lists most (get_clip lists note ids). Parts and markers can also be named. The master part is id 0 or \"master\".
- Results: every tool answers in text and in structuredContent (JSON); prefer the JSON when you read values back.
- Time: a JSON number is beats (quarter notes) from the start, 0 being the start. A string counts bars and beats from 1, in any of \"5.1\", \"5:1\", \"bar 5 beat 1\" (bar 5, beat 1). Note starts are relative to their clip; in the compact note strings (\"C4 2.5 1/8 90\") a bare number is beats and bar:beat takes a colon (\"1:3\"). Lengths may be beats, \"2 bars\" or a note value \"1/8\" (a whole note is 4 beats).
- Pitches: note names with octave, middle C = C4 = MIDI 60; sharps # and flats b; chords as \"C4+E4+G4\".
- Volumes and send levels in dB, pan -1..1. Device parameters in each parameter's own range (get_device).
- Sound: a MIDI part needs an instrument device (built-in `synth` or `drums`, or a plugin) to make sound. diagnose says what will not be heard.
- Every typed write is one undo step named `mcp: ...` and is rolled back if it fails; use batch for several as one step. Results show the state afterwards, so there is no need to read again. undo says what it undid, and lists the history.
- To check what you made, render it: the result measures loudness (LUFS), peaks, level per bar and spectrum.
- The manual and an API reference are resources: paw://help/<page>, paw://reference/api, paw://reference/lua/<module>.";
