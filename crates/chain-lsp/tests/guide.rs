//! The how-to guide for Neovim (docs/how-to/check-chain-files-in-another-editor.md):
//! the server takes the command line of the guide's configuration, and the
//! guide's example file gets the error that the guide promises. A package
//! of the crate has no docs folder, so Cargo.toml leaves this file out.
#![cfg_attr(test, expect(clippy::cast_possible_truncation, reason = "debt: pay down"))]

use std::io::BufReader;
use std::process::{Command, Stdio};

use lsp_server::{Message, Notification, Request, RequestId};
use serde_json::json;

const GUIDE: &str = include_str!("../../../docs/how-to/check-chain-files-in-another-editor.md");

/// The text between `start` and the next `end` of the guide.
fn between<'a>(start: &str, end: &str) -> &'a str {
    let from = GUIDE
        .find(start)
        .unwrap_or_else(|| panic!("the guide has {start:?}"))
        + start.len();
    let to = GUIDE[from..].find(end).expect("the end of the part") + from;
    &GUIDE[from..to]
}

#[test]
fn the_neovim_guide_starts_the_server_and_its_example_gets_its_error() {
    // The words of `cmd` up to the path of the schema, which the test gives.
    let cmd = between("cmd = { ", " vim.fs.normalize");
    let words: Vec<&str> = cmd
        .split(',')
        .map(|word| word.trim().trim_matches('"'))
        .filter(|w| !w.is_empty())
        .collect();
    assert_eq!(words, ["chain-lsp", "--schema"], "the guide's command");
    // The example, without the indent of the list item.
    let example: String = between("```text\n", "```")
        .lines()
        .map(|line| format!("{}\n", line.trim_start()))
        .collect();
    assert!(
        GUIDE.contains("as an error with the code `E202`"),
        "the guide's promise"
    );

    let dir = tempfile::tempdir().unwrap();
    std::fs::write(
        dir.path().join("schema.json"),
        include_str!("fixtures/schema.json"),
    )
    .unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_chain-lsp"))
        .args([words[1], "schema.json"])
        .env_clear()
        .current_dir(dir.path())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("chain-lsp starts");
    let mut input = child.stdin.take().unwrap();
    let mut output = BufReader::new(child.stdout.take().unwrap());
    let mut send = |message: Message| message.write(&mut input).expect("chain-lsp reads");
    let mut read = || {
        Message::read(&mut output)
            .expect("chain-lsp writes")
            .expect("a message")
    };

    send(
        Request::new(
            RequestId::from(1),
            "initialize".into(),
            json!({ "capabilities": {} }),
        )
        .into(),
    );
    read();
    send(Notification::new("initialized".into(), json!({})).into());
    let document =
        json!({ "uri": "file:///bus.chain", "languageId": "chain", "version": 1, "text": example });
    send(
        Notification::new(
            "textDocument/didOpen".into(),
            json!({ "textDocument": document }),
        )
        .into(),
    );
    let Message::Notification(published) = read() else {
        panic!("the diagnostics")
    };
    let diagnostic = &published.params["diagnostics"][0];
    assert_eq!(diagnostic["code"], "E202");
    let start = &diagnostic["range"]["start"];
    let line = example
        .lines()
        .nth(start["line"].as_u64().unwrap() as usize)
        .unwrap();
    assert!(
        line[start["character"].as_u64().unwrap() as usize..].starts_with("thresh="),
        "on `thresh`"
    );

    send(
        Request::new(
            RequestId::from(2),
            "shutdown".into(),
            serde_json::Value::Null,
        )
        .into(),
    );
    read();
    send(Notification::new("exit".into(), serde_json::Value::Null).into());
    assert!(child.wait().unwrap().success());
}
