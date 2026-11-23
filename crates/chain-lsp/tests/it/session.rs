//! A session of an editor with the server: diagnostics, formatting,
//! completion, hover, definition, and where the schema comes from.

use chain_lsp::{Options, SchemaSource};
use serde_json::{Value, json};

use crate::{Client, SCHEMA, URI};

/// A chain with an unknown parameter and a value out of range. The check
/// runs only on a text with no error of the grammar.
const BAD: &str = "\
chain 1
compressor #1 ratio=4 thresh=-20dB
saturation #2 drive=40dB curve=tube
";

/// The code, the place and the message of each diagnostic, one on a line.
fn summary(published: &Value) -> Vec<String> {
    published["diagnostics"]
        .as_array()
        .expect("a list of diagnostics")
        .iter()
        .map(|d| {
            let start = &d["range"]["start"];
            format!(
                "{}:{} {} {}",
                start["line"],
                start["character"],
                d["code"].as_str().unwrap(),
                d["message"].as_str().unwrap()
            )
        })
        .collect()
}

#[test]
fn a_text_that_opens_or_changes_gets_the_diagnostics_of_the_golden_file() {
    let dir = tempfile::tempdir().unwrap();
    let mut client = Client::with_schema_file(dir.path());
    insta::assert_json_snapshot!(client.open(BAD));
    let fixed = BAD.replace("thresh=", "threshold=").replace("40dB", "30dB");
    let document = json!({ "uri": URI, "version": 2 });
    client.notify(
        "textDocument/didChange",
        json!({ "textDocument": document, "contentChanges": [{ "text": fixed }] }),
    );
    let published = client.next("textDocument/publishDiagnostics");
    assert_eq!(summary(&published), Vec::<String>::new(), "the fixed text");
    assert_eq!(published["version"], 2, "of the version that changed");
}

#[test]
fn formatting_gives_the_layout_of_the_schema_and_leaves_a_text_with_an_error() {
    let dir = tempfile::tempdir().unwrap();
    let mut client = Client::with_schema_file(dir.path());
    client.open("chain 1\n-- the glue\nsaturation   curve=tape drive=6dB  ratio=2\n");
    let edits = client.request("textDocument/formatting", json!({ "textDocument": { "uri": URI }, "options": { "tabSize": 2, "insertSpaces": true } }));
    // The fields in the order of the schema, the default drive left out,
    // and the comment kept.
    assert_eq!(
        edits[0]["newText"],
        "chain 1\n-- the glue\nsaturation curve=tape ratio=2\n"
    );
    assert_eq!(
        edits[0]["range"],
        json!({ "start": { "line": 0, "character": 0 }, "end": { "line": 3, "character": 0 } })
    );
    client.open("chain 1\nrack !\n");
    let edits = client.request("textDocument/formatting", json!({ "textDocument": { "uri": URI }, "options": { "tabSize": 2, "insertSpaces": true } }));
    assert_eq!(edits, Value::Null, "a text with an error");
}

#[test]
fn completion_offers_the_parameters_of_the_kind_of_the_line() {
    let dir = tempfile::tempdir().unwrap();
    let mut client = Client::with_schema_file(dir.path());
    let items = client.at("textDocument/completion", "chain 1\ncompressor ratio=4 th$");
    assert_eq!(
        items,
        json!([{
            "label": "threshold",
            "kind": 10,
            "detail": "a number in dB from -60 to 0, default -18",
            "textEdit": {
                "range": { "start": { "line": 1, "character": 19 }, "end": { "line": 1, "character": 21 } },
                "newText": "threshold="
            }
        }])
    );
}

#[test]
fn hover_shows_the_range_and_unit_of_a_parameter() {
    let dir = tempfile::tempdir().unwrap();
    let mut client = Client::with_schema_file(dir.path());
    let hover = client.at("textDocument/hover", "chain 1\nsaturation dri$ve=12dB");
    assert_eq!(
        hover["contents"]["value"],
        "`drive`  \na number in dB from 0 to 36, default 6"
    );
    assert_eq!(
        hover["range"],
        json!({ "start": { "line": 1, "character": 11 }, "end": { "line": 1, "character": 16 } })
    );
}

#[test]
fn definition_goes_from_a_reference_to_its_node() {
    let dir = tempfile::tempdir().unwrap();
    let mut client = Client::with_schema_file(dir.path());
    let location = client.at(
        "textDocument/definition",
        "chain 1\nsaturation #grit\ncompressor key=@gr$it\n",
    );
    assert_eq!(
        location,
        json!({ "uri": URI, "range": { "start": { "line": 1, "character": 11 }, "end": { "line": 1, "character": 16 } } })
    );
}

#[test]
fn the_schema_of_the_client_comes_before_the_command_line_and_runs_its_command() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("schema.json");
    std::fs::write(&path, SCHEMA).unwrap();
    // The command line names a file that does not exist: the client's
    // command is the one that runs.
    let options = Options {
        schema: Some(SchemaSource::File(dir.path().join("missing.json"))),
    };
    let command = json!({ "schemaCommand": ["cat", path] });
    let mut client = Client::start(options, command);
    let published = client.open("chain 1\nreverb size=2\n");
    assert_eq!(
        summary(&published),
        ["1:0 E201 no kind `reverb`"],
        "checked against the schema"
    );
    assert_eq!(client.messages, Vec::<String>::new(), "no warning");
}

#[test]
fn without_a_schema_the_server_says_so_and_checks_the_grammar_only() {
    let options = Options {
        schema: Some(SchemaSource::Command(vec!["false".into()])),
    };
    let mut client = Client::start(options, Value::Null);
    let published = client.open("chain 1\nreverb size=2 !\n");
    assert_eq!(
        summary(&published),
        ["1:14 E106 `!` cannot start a token here"],
        "the grammar only"
    );
    assert_eq!(
        client.messages.len(),
        1,
        "one warning: {:?}",
        client.messages
    );
    assert!(
        client.messages[0].starts_with("chain-lsp: the schema command `false` failed"),
        "{:?}",
        client.messages
    );
}

#[test]
fn the_context_of_the_part_gives_the_lanes_and_a_new_context_checks_the_open_text_again() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("schema.json");
    std::fs::write(&path, SCHEMA).unwrap();
    let options = Options {
        schema: Some(SchemaSource::File(path)),
    };
    let context = json!({ "chain_context": 2, "lanes": [{ "name": "Notes", "stream": "midi" }] });
    let mut client = Client::start(options, json!({ "chainContext": context }));
    let published = client.open("chain 2\nstrip #1\n\"Notes\" -> #1\n#1 => \"Print\"\n");
    assert_eq!(
        summary(&published),
        [
            "3:0 W302 the context of the host has no lane \"Print\" in this part: its type is not checked"
        ],
        "the lane of the context is known"
    );
    client.notify(
        "chain/context",
        json!({ "chain_context": 2, "lanes": [{ "name": "Print", "stream": "audio" }] }),
    );
    let published = client.next("textDocument/publishDiagnostics");
    assert_eq!(
        summary(&published),
        [
            "2:0 W302 the context of the host has no lane \"Notes\" in this part: its type is not checked"
        ],
        "the new context, on the text that is open"
    );
    let lanes = client.at("textDocument/completion", "chain 2\nstrip #1\n#1 => \"P$\n");
    assert_eq!(lanes[0]["label"], "\"Print\"");
}
