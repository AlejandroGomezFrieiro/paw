//! Speaks MCP to `paw-mcp` over stdio, with a headless kernel on the null
//! audio backend behind it: the handshake, the tool list, a short song built
//! with typed tools only, a render, undo, and the ways calls go wrong.

#![expect(clippy::unwrap_used, reason = "test code: a failed unwrap is a failed test")]
#![cfg_attr(test, expect(clippy::cast_possible_truncation, reason = "debt: pay down"))]
#![cfg_attr(test, expect(clippy::cast_precision_loss, reason = "debt: pay down"))]

mod sealed;

use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::{Value, json};

/// The `paw` binary, built beside this crate's when it is not there yet.
fn paw_binary() -> PathBuf {
    if let Some(path) = std::env::var_os("PAW_BIN") {
        return path.into();
    }
    let dir = Path::new(env!("CARGO_BIN_EXE_paw-mcp")).parent().unwrap();
    let paw = dir.join("paw");
    if !paw.is_file() {
        let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
        let mut command = Command::new(cargo);
        command.args(["build", "-p", "paw-tui", "--bin", "paw"]);
        if dir.ends_with("release") {
            command.arg("--release");
        }
        let status = command.status().expect("running cargo build -p paw-tui");
        assert!(status.success(), "could not build the paw binary");
    }
    paw
}

/// A short directory for sockets, whose paths must fit in 108 bytes.
fn socket_dir() -> tempfile::TempDir {
    tempfile::Builder::new().prefix("dmcp-").tempdir().unwrap()
}

/// A fresh directory under the target's temporary directory.
fn scratch(name: &str) -> tempfile::TempDir {
    let base = Path::new(env!("CARGO_TARGET_TMPDIR")).canonicalize().unwrap();
    tempfile::Builder::new()
        .prefix(&format!("mcp-{name}-"))
        .tempdir_in(base)
        .unwrap()
}

const KERNEL_ARGS: [&str; 4] = ["--audio", "null", "--no-plugins", "--clean"];

struct Client {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    next: u64,
    _sockets: tempfile::TempDir,
}

impl Client {
    fn start(dir: &tempfile::TempDir, args: &[&str]) -> Self {
        let dir = dir.path();
        let sockets = socket_dir();
        let mut child = sealed::seal(&mut Command::new(env!("CARGO_BIN_EXE_paw-mcp")), dir)
            .arg("--root")
            .arg(dir)
            .arg("--paw")
            .arg(paw_binary())
            .args(args)
            .current_dir(dir)
            .env("XDG_RUNTIME_DIR", sockets.path())
            .env("XDG_CACHE_HOME", dir)
            .env("XDG_DATA_HOME", dir)
            .env("XDG_CONFIG_HOME", dir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .expect("starting paw-mcp");
        let stdin = child.stdin.take().unwrap();
        let stdout = BufReader::new(child.stdout.take().unwrap());
        Self {
            child,
            stdin,
            stdout,
            next: 1,
            _sockets: sockets,
        }
    }

    fn send(&mut self, message: &Value) {
        writeln!(self.stdin, "{message}").unwrap();
        self.stdin.flush().unwrap();
    }

    /// The next line of stdout, which must be one JSON-RPC message.
    fn receive(&mut self) -> Value {
        let mut line = String::new();
        self.stdout.read_line(&mut line).unwrap();
        assert!(!line.is_empty(), "the server closed stdout");
        let message: Value = serde_json::from_str(&line).unwrap_or_else(|err| {
            panic!("stdout carried something that is not JSON ({err}): {line}")
        });
        assert_eq!(message["jsonrpc"], "2.0", "{message}");
        message
    }

    fn request(&mut self, method: &str, params: Value) -> Value {
        let id = self.next;
        self.next += 1;
        self.send(&json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params }));
        let reply = self.receive();
        assert_eq!(reply["id"], id, "{reply}");
        reply
    }

    fn initialize(&mut self, version: &str) -> Value {
        let reply = self.request(
            "initialize",
            json!({
                "protocolVersion": version,
                "capabilities": {},
                "clientInfo": { "name": "test", "version": "0" },
            }),
        );
        self.send(&json!({ "jsonrpc": "2.0", "method": "notifications/initialized" }));
        reply["result"].clone()
    }

    /// Call a tool; returns its text and whether it reported an error.
    fn call(&mut self, name: &str, args: Value) -> (String, bool) {
        let reply = self.request("tools/call", json!({ "name": name, "arguments": args }));
        let result = &reply["result"];
        assert!(result.is_object(), "{name}: not a tool result: {reply}");
        let content = result["content"].as_array().expect("content");
        assert_eq!(content[0]["type"], "text");
        let text = content[0]["text"].as_str().unwrap().to_string();
        (text, result["isError"] == true)
    }

    fn ok(&mut self, name: &str, args: Value) -> String {
        let (text, error) = self.call(name, args.clone());
        assert!(!error, "{name} {args} failed: {text}");
        text
    }

    fn fails(&mut self, name: &str, args: Value) -> String {
        let (text, error) = self.call(name, args.clone());
        assert!(error, "{name} {args} should have failed, but said: {text}");
        text
    }

    /// Close stdin and wait for the server to exit by itself.
    fn finish(mut self) {
        drop(self.stdin);
        let deadline = Instant::now() + Duration::from_secs(15);
        loop {
            if let Some(status) = self.child.try_wait().unwrap() {
                assert!(status.success(), "paw-mcp exited with {status}");
                return;
            }
            assert!(
                Instant::now() < deadline,
                "paw-mcp did not exit when stdin closed"
            );
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}

/// Check that a value is a sound JSON Schema of the kind tools use: known
/// keywords with values of the right shape, all the way down.
fn check_schema(schema: &Value, at: &str) {
    if schema.is_boolean() {
        return;
    }
    let object = schema
        .as_object()
        .unwrap_or_else(|| panic!("{at}: a schema must be an object"));
    const TYPES: [&str; 7] = [
        "object", "array", "string", "number", "integer", "boolean", "null",
    ];
    for (key, value) in object {
        match key.as_str() {
            "type" => {
                let types: Vec<&Value> = match value {
                    Value::Array(list) => list.iter().collect(),
                    other => vec![other],
                };
                assert!(!types.is_empty(), "{at}: empty type");
                for t in types {
                    assert!(
                        TYPES.contains(&t.as_str().unwrap_or("")),
                        "{at}: bad type {t}"
                    );
                }
            }
            "description" | "title" => assert!(value.is_string(), "{at}: {key} must be a string"),
            "properties" => {
                for (name, sub) in value
                    .as_object()
                    .unwrap_or_else(|| panic!("{at}: properties"))
                {
                    assert!(
                        sub["description"].is_string() || sub["anyOf"].is_array(),
                        "{at}.{name} has no description"
                    );
                    check_schema(sub, &format!("{at}.{name}"));
                }
            }
            "required" => {
                for name in value.as_array().unwrap_or_else(|| panic!("{at}: required")) {
                    let name = name.as_str().expect("required names are strings");
                    assert!(
                        object["properties"].get(name).is_some(),
                        "{at}: required `{name}` is not a property"
                    );
                }
            }
            "items" | "additionalProperties" => check_schema(value, &format!("{at}.{key}")),
            "anyOf" => {
                for (i, sub) in value
                    .as_array()
                    .unwrap_or_else(|| panic!("{at}: {key}"))
                    .iter()
                    .enumerate()
                {
                    check_schema(sub, &format!("{at}.{key}[{i}]"));
                }
            }
            "enum" => assert!(
                value.as_array().is_some_and(|v| !v.is_empty()),
                "{at}: enum"
            ),
            "minimum" | "maximum" | "exclusiveMinimum" => assert!(value.is_number(), "{at}: {key}"),
            "minItems" | "maxItems" => assert!(value.is_u64(), "{at}: {key}"),
            other => panic!("{at}: unexpected keyword `{other}`"),
        }
    }
}

/// The peak of the left channel in dBFS, from a render's measurements.
fn left_peak(text: &str) -> f64 {
    let line = text
        .lines()
        .find(|l| l.starts_with("left: peak"))
        .unwrap_or_else(|| panic!("no levels in:\n{text}"));
    let value = line
        .trim_start_matches("left: peak ")
        .split(' ')
        .next()
        .unwrap();
    if value == "-inf" {
        -200.0
    } else {
        value.parse().unwrap()
    }
}

#[test]
#[expect(clippy::too_many_lines, reason = "one test of a long scenario, read from top to bottom")]
fn handshake_and_tool_list() {
    let dir = scratch("handshake");
    let mut client = Client::start(
        &dir,
        &[
            "--spawn",
            "--",
            "--audio",
            "null",
            "--no-plugins",
            "--clean",
        ],
    );

    // Each revision we speak is answered with itself; an unknown one with our newest.
    for version in ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"] {
        let result = client.initialize(version);
        assert_eq!(result["protocolVersion"], version);
        assert!(result["capabilities"]["tools"].is_object());
        assert_eq!(result["serverInfo"]["name"], "paw-mcp");
        assert!(result["instructions"].as_str().unwrap().contains("beats"));
    }
    assert_eq!(
        client.initialize("1999-01-01")["protocolVersion"],
        "2025-11-25"
    );
    assert_eq!(client.request("ping", json!({}))["result"], json!({}));

    let tools = client.request("tools/list", json!({}))["result"]["tools"].clone();
    let tools = tools.as_array().unwrap();
    let names: Vec<&str> = tools.iter().map(|t| t["name"].as_str().unwrap()).collect();
    for expected in [
        "get_project",
        "get_part",
        "get_clip",
        "get_device",
        "find_devices",
        "get_status",
        "add_part",
        "set_part",
        "add_clip",
        "edit_clip",
        "add_device",
        "set_device",
        "automate",
        "set_project",
        "remove",
        "transport",
        "undo",
        "project_file",
        "render",
        "analyze_audio",
        "find",
        "diagnose",
        "marker",
        "duplicate_clip",
        "repeat_bars",
        "batch",
    ] {
        assert!(names.contains(&expected), "missing tool {expected}");
    }
    // The escape hatches are not offered without --allow-eval.
    for hidden in ["lua", "run_command", "send_keys"] {
        assert!(
            !names.contains(&hidden),
            "{hidden} offered without --allow-eval"
        );
    }
    for tool in tools {
        let name = tool["name"].as_str().unwrap();
        assert!(
            name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_'),
            "{name}"
        );
        assert!(
            tool["description"].as_str().unwrap().len() > 40,
            "{name}: description too short"
        );
        let schema = &tool["inputSchema"];
        assert_eq!(schema["type"], "object", "{name}");
        assert!(schema["properties"].is_object(), "{name}");
        check_schema(schema, name);
    }

    // The 2026-07-28 revision: version and capabilities in `_meta`, no
    // handshake needed.
    let meta = json!({ "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
    } });
    let modern = client.request("tools/list", meta.clone());
    assert_eq!(modern["result"]["resultType"], "complete");
    assert_eq!(
        modern["result"]["tools"].as_array().unwrap().len(),
        tools.len()
    );
    let discover = client.request("server/discover", meta);
    let versions = discover["result"]["supportedVersions"].as_array().unwrap();
    assert!(versions.contains(&json!("2026-07-28")), "{discover}");
    let unsupported = client.request(
        "tools/list",
        json!({ "_meta": { "io.modelcontextprotocol/protocolVersion": "2099-01-01" } }),
    );
    assert_eq!(unsupported["error"]["code"], -32022);

    // Protocol errors.
    assert_eq!(
        client.request("no/such/method", json!({}))["error"]["code"],
        -32601
    );
    // An unknown tool is a tool error the model can read, not a protocol one.
    let unknown = client.request(
        "tools/call",
        json!({ "name": "no_such_tool", "arguments": {} }),
    );
    assert_eq!(unknown["result"]["isError"], true);
    assert!(unknown["result"]["content"][0]["text"].as_str().unwrap().contains("get_project"));
    client.send(&json!("not a request"));
    assert_eq!(client.receive()["error"]["code"], -32600);
    // A line that is not JSON has no id to answer: it is passed over.
    writeln!(client.stdin, "{{ this is not json").unwrap();
    client.stdin.flush().unwrap();
    assert_eq!(client.request("ping", json!({}))["result"], json!({}));
    client.finish();
}

#[test]
#[expect(clippy::too_many_lines, reason = "one test of a long scenario, read from top to bottom")]
fn build_render_undo() {
    let dir = scratch("song");
    let mut args = vec!["--spawn", "--"];
    args.extend(KERNEL_ARGS);
    let mut c = Client::start(&dir, &args);
    c.initialize("2025-06-18");

    let text = c.ok(
        "set_project",
        json!({ "tempo": 110, "signature": "4/4", "name": "Test song" }),
    );
    assert!(text.contains("110 BPM"), "{text}");

    // A bass part with its instrument and a two-bar riff, in one call.
    let text = c.ok(
        "add_part",
        json!({
            "name": "Bass",
            "volume": -3,
            "devices": [{ "kind": "synth", "params": { "wave": "saw", "cutoff": 900 } }],
            "clips": [{ "name": "riff", "start": 0, "length": "2 bars", "notes": [
                "A1 0 1/8", "A1 0.5 1/8", "C2 1:2 1/4 90", "E2 1:3 1/4", "G1 4 2",
                { "pitch": "A1", "start": "2.3", "length": 1, "velocity": 110 }
            ]}]
        }),
    );
    assert!(text.contains("\"Bass\""), "{text}");
    assert!(text.contains("6 notes (G1–E2)"), "{text}");
    let bass_synth = id_after(&text, "devices: [id ");
    let riff = id_after(&text, "clips:\n     [id ");

    let text = c.ok("add_part", json!({
        "name": "Drums",
        "devices": ["drums"],
        "clips": [{ "start": "1.1", "length": 8, "notes": ["C2 0", "D2 1", "C2 2", "D2 3", "F#2 0 1/8", "F#2 2 1/8"] }]
    }));
    assert!(text.contains("\"Drums\""), "{text}");

    let text = c.ok(
        "add_part",
        json!({ "name": "Echo", "devices": [{ "kind": "delay", "params": { "mix": 1 } }] }),
    );
    assert!(text.contains("Delay"), "{text}");
    let text = c.ok(
        "set_part",
        json!({ "part": "bass", "sends": [{ "target": "Echo", "level": -10 }], "pan": -0.25 }),
    );
    assert!(text.contains("sends: \"Echo\""), "{text}");
    assert!(text.contains("pan -0.25"), "{text}");

    let text = c.ok(
        "set_device",
        json!({ "device": bass_synth, "params": { "resonance": 0.4, "release": 99 } }),
    );
    assert!(text.contains("resonance: 0.4"), "{text}");
    assert!(
        text.contains("release: 5 s"),
        "clamped to the range: {text}"
    );

    let text = c.ok(
        "edit_clip",
        json!({ "clip": riff, "add_notes": ["E2 6 1"], "remove_notes": { "pitches": ["G1"] } }),
    );
    assert!(text.contains("6 notes"), "{text}");
    assert!(text.contains("(1 note removed)"), "{text}");

    // Read it back.
    let text = c.ok("get_project", json!({}));
    for expected in [
        "Test song",
        "\"Bass\"",
        "\"Drums\"",
        "\"Echo\"",
        "110 BPM",
        "Synth (synth)",
        "Drums (drums)",
    ] {
        assert!(
            text.contains(expected),
            "get_project lacks {expected}:\n{text}"
        );
    }
    let text = c.ok("get_clip", json!({ "clip": riff }));
    assert!(text.contains("A1 0 0.5 100  (1.1)"), "{text}");
    assert!(text.contains("A1 6 1 110  (2.3)"), "{text}");
    let text = c.ok(
        "get_device",
        json!({ "device": bass_synth, "filter": "cut" }),
    );
    assert!(text.contains("cutoff: 900 Hz (range 20 to 20000"), "{text}");
    let text = c.ok("find_devices", json!({ "query": "drum" }));
    assert!(text.contains("drums — Drums"), "{text}");

    // Render, and hear it in numbers.
    let text = c.ok("render", json!({ "path": "out/mix.wav", "tail": 0.5 }));
    assert!(dir.path().join("out/mix.wav").is_file(), "{text}");
    assert!(!text.contains("SILENT"), "{text}");
    assert!(left_peak(&text) > -40.0, "{text}");
    assert!(text.contains("level over time (bars"), "{text}");
    assert!(text.contains("spectral centroid"), "{text}");

    // Automation, then undo it: the lane is gone and the clip still there.
    let text = c.ok(
        "automate",
        json!({ "part": "Bass", "points": [[0, -40], ["2.1", 0]] }),
    );
    assert!(text.contains("New automation"), "{text}");
    assert!(
        c.ok("get_part", json!({ "part": "Bass" }))
            .contains("automation:")
    );
    let text = c.ok("undo", json!({}));
    assert!(text.contains("Undid 1 step"), "{text}");
    let part = c.ok("get_part", json!({ "part": "Bass" }));
    assert!(!part.contains("automation:"), "{part}");
    assert!(part.contains("\"riff\""), "{part}");
    assert!(
        c.ok("undo", json!({ "redo": true }))
            .contains("Redid 1 step")
    );

    // A call that fails part-way changes nothing.
    let before = c.ok("get_project", json!({}));
    let text = c.fails(
        "add_part",
        json!({ "name": "Broken", "devices": ["synth", "no such device at all"] }),
    );
    assert!(text.contains("rolled back"), "{text}");
    assert_eq!(c.ok("get_project", json!({})), before);

    // Bad arguments come back as tool errors the model can act on.
    assert!(
        c.fails("add_clip", json!({ "part": "Bass", "strat": 0 }))
            .contains("unknown argument `strat`")
    );
    assert!(
        c.fails("add_clip", json!({ "part": "Bass", "notes": ["H9 0"] }))
            .contains("not a note name")
    );
    assert!(
        c.fails("add_clip", json!({ "part": "Bass", "start": "0.5" }))
            .contains("bar 3 beat 1")
    );
    assert!(
        c.fails("get_clip", json!({ "clip": 99999 }))
            .contains("no clip 99999")
    );
    assert!(
        c.fails("set_part", json!({ "part": "Nobody" }))
            .contains("no part named")
    );
    assert!(
        c.fails("get_part", json!({}))
            .contains("missing required argument `part`")
    );
    assert!(
        c.fails("lua", json!({ "code": "1" }))
            .contains("--allow-eval")
    );
    assert!(
        c.fails("render", json!({ "path": "../outside.wav" }))
            .contains("outside the working directory")
    );
    assert!(
        c.fails(
            "project_file",
            json!({ "action": "save", "path": "/tmp/x.json" })
        )
        .contains("outside")
    );

    // Save, and refuse to throw away unsaved work.
    let text = c.ok(
        "project_file",
        json!({ "action": "save", "path": "song.json" }),
    );
    assert!(dir.path().join("song.json").is_file(), "{text}");
    c.ok("set_part", json!({ "part": "Drums", "mute": true }));
    assert!(
        c.fails("project_file", json!({ "action": "new" }))
            .contains("unsaved")
    );
    let text = c.ok(
        "project_file",
        json!({ "action": "open", "path": "song.json", "discard": true }),
    );
    assert!(text.contains("\"Drums\""), "{text}");
    assert!(!text.contains("MUTED"), "{text}");
    c.finish();
}

#[test]
fn escape_hatches_with_allow_eval() {
    let dir = scratch("eval");
    let mut args = vec!["--spawn", "--allow-eval", "--"];
    args.extend(KERNEL_ARGS);
    let mut c = Client::start(&dir, &args);
    c.initialize("2025-03-26");
    let tools = c.request("tools/list", json!({}))["result"]["tools"].clone();
    assert!(
        tools
            .as_array()
            .unwrap()
            .iter()
            .any(|t| t["name"] == "lua")
    );
    assert_eq!(c.ok("lua", json!({ "code": "1 + 2" })), "3");
    let text = c.ok("run_command", json!({ "line": "tempo 97" }));
    assert!(text.contains("one undo step"), "{text}");
    assert!(c.ok("get_project", json!({})).contains("97 BPM"));
    assert!(
        c.fails("lua", json!({ "code": "error('boom')" }))
            .contains("boom")
    );
    c.ok("send_keys", json!({ "keys": "gg" }));

    // The kernel this server started goes away: the next call starts another
    // and says so.
    c.ok("lua", json!({ "code": "paw.api.quit(0)" }));
    std::thread::sleep(Duration::from_millis(300));
    let text = c.ok("get_project", json!({}));
    assert!(
        text.starts_with("NOTE: The kernel this server started had stopped"),
        "{text}"
    );
    assert!(text.contains("120 BPM"), "a fresh project: {text}");
    c.finish();
}

/// The server attaches to a kernel it did not start, reports when it is
/// gone, and carries on when one is back.
#[test]
fn kernel_gone_and_back() {
    let dir = scratch("gone");
    let sockets = socket_dir();
    let socket = sockets.path().join("k.sock");
    let kernel = || {
        let child = sealed::seal(&mut Command::new(paw_binary()), dir.path())
            .args(["--headless", "--listen"])
            .arg(&socket)
            .args(KERNEL_ARGS)
            .env("XDG_CACHE_HOME", dir.path())
            .env("XDG_DATA_HOME", dir.path())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(60);
        while std::os::unix::net::UnixStream::connect(&socket).is_err() {
            assert!(Instant::now() < deadline, "the kernel did not start");
            std::thread::sleep(Duration::from_millis(20));
        }
        child
    };
    let mut c = Client::start(&dir, &["--socket", socket.to_str().unwrap()]);
    c.initialize("2025-11-25");
    let text = c.fails("get_project", json!({}));
    assert!(text.contains("No paw kernel at"), "{text}");

    let mut k = kernel();
    c.ok("add_part", json!({ "name": "First" }));
    k.kill().unwrap();
    k.wait().unwrap();
    let text = c.fails("get_project", json!({}));
    assert!(text.contains("No paw kernel"), "{text}");

    let mut k = kernel();
    let text = c.ok("get_project", json!({}));
    assert!(text.contains("Parts (0)"), "a fresh kernel: {text}");
    c.finish();
    k.kill().unwrap();
    k.wait().unwrap();
}

/// The number after `marker` in `text`.
fn id_after(text: &str, marker: &str) -> u64 {
    let at = text
        .find(marker)
        .unwrap_or_else(|| panic!("no `{marker}` in:\n{text}"))
        + marker.len();
    text[at..]
        .chars()
        .take_while(char::is_ascii_digit)
        .collect::<String>()
        .parse()
        .unwrap()
}

impl Client {
    /// A tool's structured result; the call must not have failed.
    fn data(&mut self, name: &str, args: Value) -> Value {
        let reply = self.request("tools/call", json!({ "name": name, "arguments": args }));
        let result = &reply["result"];
        assert_eq!(result["isError"], false, "{name}: {result}");
        assert!(result["content"][0]["text"].as_str().is_some());
        assert!(result["structuredContent"].is_object(), "{name}: {result}");
        result["structuredContent"].clone()
    }

    fn add_drums(&mut self) {
        self.ok(
            "add_part",
            json!({
                "name": "Drums", "devices": ["drums"],
                "clips": [{ "start": 4, "length": 4, "notes": ["C2 0", "D2 1", "C2 2", "D2 3"] }]
            }),
        );
    }
}

fn pitches_of(data: &Value) -> Vec<u64> {
    data["clip"]["notes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|n| n["pitch"].as_u64().unwrap())
        .collect()
}

#[test]
#[expect(clippy::too_many_lines, reason = "one test of a long scenario, read from top to bottom")]
fn an_agent_composes_with_json_ids_markers_and_one_step_batches() {
    let dir = scratch("agent");
    let mut args = vec!["--spawn", "--"];
    args.extend(KERNEL_ARGS);
    let mut c = Client::start(&dir, &args);
    c.initialize("2025-06-18");

    // Results are JSON as well as prose; empty lists are lists.
    let p = c.data("get_project", json!({}));
    assert_eq!(p["project"]["parts"], json!([]));
    assert_eq!(p["project"]["markers"], json!([]));

    // Time in every syntax means the same place; the key is the project's.
    c.ok("set_project", json!({ "key": "D minor", "tempo": 120 }));
    let d = c.data(
        "add_part",
        json!({
            "name": "Lead", "devices": ["synth"],
            "clips": [{ "name": "tune", "start": "bar 2 beat 1", "length": "2 bars",
                        "notes": ["D4 0 1", "F4 1 1", "A4 2 1", "C5 3 1 80"] }]
        }),
    );
    let clip = &d["part"]["clips"][0];
    assert_eq!(clip["start"], 4.0);
    assert_eq!(clip["at"], "2.1");
    let id = clip["id"].as_u64().unwrap();
    for start in ["2.1", "2:1", "bar 2 beat 1", "bar 2"] {
        let t = c.data(
            "add_clip",
            json!({ "part": "Lead", "start": start, "notes": ["C4 0 1"] }),
        );
        assert_eq!(t["clip"]["start"], 4.0, "{start}");
    }

    // Note ids, and one note edited by its id.
    let got = c.data("get_clip", json!({ "clip": id }));
    let notes = got["clip"]["notes"].as_array().unwrap().clone();
    assert_eq!(notes.len(), 4);
    assert_eq!(notes[1]["name"], "F4");
    let f4 = notes[1]["id"].as_u64().unwrap();
    let c5 = notes[3]["id"].as_u64().unwrap();
    let e = c.data(
        "edit_clip",
        json!({ "clip": id, "edit_notes": [{ "id": f4, "pitch": "G4", "length": "1/8" }] }),
    );
    let moved = e["clip"]["notes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|n| n["id"] == f4)
        .unwrap()
        .clone();
    assert_eq!((moved["pitch"].as_u64(), moved["length"].as_f64()), (Some(67), Some(0.5)));
    // Absolute velocity over a pitch range, and the filter of get_clip.
    c.ok(
        "edit_clip",
        json!({ "clip": id, "set_velocity": { "value": 64, "pitches": ["A4", "C5"] } }),
    );
    let got = c.data("get_clip", json!({ "clip": id, "pitches": ["C5"] }));
    assert_eq!(got["clip"]["notes"].as_array().unwrap().len(), 1);
    assert_eq!(got["clip"]["notes"][0]["velocity"], 64);
    assert_eq!(got["clip"]["notes"][0]["id"], c5);
    c.fails(
        "edit_clip",
        json!({ "clip": id, "edit_notes": [{ "id": 99999, "pitch": 60 }] }),
    );

    // A third up in D minor stays in D minor: D4 G4 A4 C5 -> F4 Bb4 C5 E5.
    let was = pitches_of(&c.data("get_clip", json!({ "clip": id })));
    assert_eq!(was, vec![62, 67, 69, 72]);
    let t = c.data("edit_clip", json!({ "clip": id, "transpose": { "degrees": 2 } }));
    assert_eq!(pitches_of(&t), vec![65, 70, 72, 76]);
    // Chromatic transpose still takes an integer.
    let t = c.data("edit_clip", json!({ "clip": id, "transpose": -12 }));
    assert_eq!(pitches_of(&t), vec![53, 58, 60, 64]);

    // Markers and regions: add, rename, move, list, remove; loop by region.
    c.data("marker", json!({ "action": "add", "at": "1.1", "name": "Intro", "length": "1 bar" }));
    let m = c.data(
        "marker",
        json!({ "action": "add", "at": "bar 2", "name": "Verse", "length": "2 bars" }),
    );
    assert_eq!(m["markers"].as_array().unwrap().len(), 2);
    let verse = m["marker"]["id"].as_u64().unwrap();
    assert_eq!(m["marker"]["beat"], 4.0);
    let m = c.data("marker", json!({ "action": "rename", "marker": verse, "name": "Verse 1" }));
    assert_eq!(m["marker"]["name"], "Verse 1");
    c.data("marker", json!({ "action": "move", "marker": "Intro", "at": 0, "length": 4 }));
    assert!(c.ok("get_project", json!({})).contains("region \"Verse 1\""));
    let t = c.data("transport", json!({ "loop_marker": "Verse 1" }));
    assert_eq!(t["transport"]["loop_start"], 4.0);
    assert_eq!(t["transport"]["loop_end"], 12.0);
    assert_eq!(t["transport"]["loop_enabled"], true);
    c.fails("marker", json!({ "action": "remove", "marker": "Nope" }));

    // Render options: a region, LUFS in the answer, FLAC, a loudness target, stems.
    let text = c.ok("render", json!({ "path": "v.wav", "region": "Verse 1", "tail": 0.2 }));
    assert!(text.contains("LUFS integrated"), "{text}");
    assert!(text.contains("beats 4 (2.1) to 12 (4.1)"), "{text}");
    let flac = c.ok(
        "render",
        json!({ "path": "v.flac", "region": "Verse 1", "loudness": -20 }),
    );
    assert!(dir.path().join("v.flac").is_file() && flac.contains("-20"), "{flac}");
    c.add_drums();
    let stems = c.ok("render", json!({ "path": "stems", "stems": true, "tail": 0 }));
    assert!(stems.contains("Lead.wav: peak") && stems.contains("Drums.wav"), "{stems}");
    assert!(dir.path().join("stems/Lead.wav").is_file());
    let an = c.ok("analyze_audio", json!({ "path": "v.flac" }));
    assert!(an.contains("LUFS"), "{an}");

    // Duplicate a clip, repeat a stretch.
    let d = c.data("duplicate_clip", json!({ "clip": id, "times": 2 }));
    assert_eq!(d["clips"].as_array().unwrap().len(), 2);
    assert_eq!(d["clips"][0]["start"], 12.0);
    let r = c.data("repeat_bars", json!({ "from": "2.1", "to": "4.1", "at": "20" }));
    assert!(!r["clips"].as_array().unwrap().is_empty());
    assert!(c
        .fails("repeat_bars", json!({ "from": "4.1", "to": "2.1" }))
        .contains("after"));

    // Find and diagnose.
    let f = c.data("find", json!({ "query": "note[pitch>=c4]" }));
    assert!(f["total"].as_u64().unwrap() >= 1, "{f}");
    c.fails("find", json!({ "query": "note[" }));
    c.ok(
        "add_part",
        json!({ "name": "Strings", "clips": [{ "start": 0, "notes": ["C4 0 1"] }] }),
    );
    c.ok("add_part", json!({ "name": "Blank" }));
    let dg = c.data("diagnose", json!({}));
    let found = dg["findings"].as_array().unwrap().clone();
    assert!(found.iter().any(|f| f["rule"] == "empty_part"), "{dg}");
    let silent = found.iter().find(|f| f["rule"] == "silent_midi_part").unwrap();
    assert!(silent["message"].as_str().unwrap().contains("Strings"));
    let dg = c.data("diagnose", json!({ "measure": true }));
    assert!(dg["measure"]["integrated"].is_number(), "{dg}");
    c.ok("set_part", json!({ "part": "Lead", "sends": [{ "target": "Blank" }] }));
    c.ok("set_part", json!({ "part": "Blank", "mute": true }));
    let dg = c.data("diagnose", json!({}));
    assert!(
        dg["findings"].as_array().unwrap().iter().any(|f| f["rule"] == "muted_destination"),
        "{dg}"
    );

    // A batch is one named undo step, and a failing one changes nothing.
    let before = c.ok("get_project", json!({}));
    let text = c.ok(
        "batch",
        json!({ "label": "verse bass", "steps": [
            { "tool": "add_part", "arguments": { "name": "Bass", "devices": ["synth"] } },
            { "tool": "add_clip", "arguments": { "part": "Bass", "notes": ["A1 0 1"] } },
            { "tool": "marker", "arguments": { "action": "add", "at": 8, "name": "Bass in" } },
        ]}),
    );
    assert!(text.contains("mcp: verse bass"), "{text}");
    let list = c.data("undo", json!({ "list": true }));
    assert_eq!(list["history"][0]["label"], "mcp: verse bass");
    assert_eq!(list["history"][1]["label"], "mcp: set_part Blank");
    let undone = c.ok("undo", json!({}));
    assert!(undone.contains("Undid 1 step: mcp: verse bass"), "{undone}");
    assert_eq!(c.ok("get_project", json!({})), before);
    let redo = c.data("undo", json!({ "list": true }));
    assert_eq!(redo["redoable"][0]["label"], "mcp: verse bass");
    c.ok("undo", json!({ "redo": true }));
    let text = c.fails(
        "batch",
        json!({ "steps": [
            { "tool": "add_part", "arguments": { "name": "Doomed" } },
            { "tool": "set_part", "arguments": { "part": "Nobody", "mute": true } },
        ]}),
    );
    assert!(text.contains("step 2"), "{text}");
    assert!(!c.ok("get_project", json!({})).contains("Doomed"));
    c.fails(
        "batch",
        json!({ "steps": [{ "tool": "render", "arguments": {} }] }),
    );

    // Per-part meter in get_part; nothing to undo is an error.
    assert!(c.ok("get_part", json!({ "part": "Lead" })).contains("meter now"));
    for _ in 0..50 {
        let (_, error) = c.call("undo", json!({ "steps": 100 }));
        if error {
            break;
        }
    }
    assert!(c.fails("undo", json!({})).contains("Nothing to undo"));
    c.finish();
}

#[test]
fn the_manual_and_the_api_are_resources() {
    let dir = scratch("resources");
    let mut args = vec!["--spawn", "--"];
    args.extend(KERNEL_ARGS);
    let mut c = Client::start(&dir, &args);
    let init = c.initialize("2025-06-18");
    assert!(init["capabilities"]["resources"].is_object());
    let api = c.request("resources/read", json!({ "uri": "paw://reference/api" }));
    let text = api["result"]["contents"][0]["text"].as_str().unwrap();
    assert!(text.contains("### `part_add("), "{}", &text[..300.min(text.len())]);
    let lua = c.request("resources/read", json!({ "uri": "paw://reference/lua/harmony" }));
    assert!(lua["result"]["contents"][0]["text"]
        .as_str()
        .unwrap()
        .contains("paw.harmony.key(beat, latest)"));
    let list = c.request("resources/list", json!({}))["result"]["resources"].clone();
    let uris: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["uri"].as_str().unwrap())
        .collect();
    assert!(uris.contains(&"paw://reference/api"));
    let page = uris.iter().find(|u| u.starts_with("paw://help/")).copied();
    let page = page.expect("the manual's pages are listed");
    let r = c.request("resources/read", json!({ "uri": page }));
    assert!(r["result"]["contents"][0]["text"].as_str().unwrap().len() > 100, "{r}");
    assert!(c.request("resources/read", json!({ "uri": "paw://nope" }))["error"].is_object());
    let templates = c.request("resources/templates/list", json!({}));
    assert!(templates["result"]["resourceTemplates"].as_array().unwrap().len() >= 2);
    c.finish();
}

/// The lists come whole, so a cursor is never valid, and each entry has the
/// title and description that a client shows. No kernel is needed: the
/// server attaches to a socket that nobody listens on.
#[test]
fn lists_refuse_a_cursor_and_give_titles() {
    let dir = scratch("lists");
    let socket = dir.path().join("nobody.sock");
    let mut c = Client::start(&dir, &["--socket", socket.to_str().unwrap()]);
    c.initialize("2025-11-25");

    for method in ["tools/list", "resources/list", "resources/templates/list"] {
        let reply = c.request(method, json!({ "cursor": "not-ours" }));
        assert_eq!(reply["error"]["code"], -32602, "{method}: {reply}");
    }

    let resources = c.request("resources/list", json!({}))["result"]["resources"].clone();
    let templates =
        c.request("resources/templates/list", json!({}))["result"]["resourceTemplates"].clone();
    let entries: Vec<&Value> =
        resources.as_array().unwrap().iter().chain(templates.as_array().unwrap()).collect();
    assert_eq!(entries.len(), 4, "the two references and the two templates");
    for entry in entries {
        for field in ["title", "description"] {
            let text = entry[field].as_str().unwrap_or("");
            assert!(!text.trim().is_empty(), "no {field}: {entry}");
        }
    }
    c.finish();
}

/// A stereo WAV with two tones on each side, in 32-bit float so that both
/// readers decode the same samples.
fn write_tones(path: &Path) {
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate: 48_000,
        bits_per_sample: 32,
        sample_format: hound::SampleFormat::Float,
    };
    let mut wav = hound::WavWriter::create(path, spec).unwrap();
    let tone = |hz: f64, i: usize| (2.0 * std::f64::consts::PI * hz * i as f64 / 48_000.0).sin();
    for i in 0..96_000 {
        let left = 0.5 * tone(220.0, i) + 0.1 * tone(3_000.0, i);
        let right = 0.3 * tone(110.0, i) - 0.4 * tone(8_000.0, i);
        wav.write_sample(left as f32).unwrap();
        wav.write_sample(right as f32).unwrap();
    }
    wav.finalize().unwrap();
}

/// The number after `label` in `text`.
fn number_after(text: &str, label: &str) -> f64 {
    let (_, rest) = text
        .split_once(label)
        .unwrap_or_else(|| panic!("no {label:?} in:\n{text}"));
    rest.split_whitespace().next().unwrap().parse().unwrap()
}

/// `:mix` (the kernel's `paw.api.measure`) and the MCP's `analyze_audio`
/// read one file alike: the sample peak and each octave band. The MCP text
/// gives one decimal, so the numbers agree to its rounding.
#[test]
fn analyze_audio_and_mix_give_the_same_numbers() {
    let dir = scratch("measure");
    let file = dir.path().join("tones.wav");
    write_tones(&file);
    let mut args = vec!["--spawn", "--allow-eval", "--"];
    args.extend(KERNEL_ARGS);
    let mut c = Client::start(&dir, &args);
    c.initialize("2025-03-26");

    let text = c.ok("analyze_audio", json!({ "path": "tones.wav" }));
    let code = format!(
        "local m = paw.api.measure({{ file = {:?} }})
         local out = {{ string.format('peak %.6f', m.sample_peak) }}
         for _, b in ipairs(m.bands) do out[#out + 1] = string.format('%s %.6f', b.name, b.share) end
         return table.concat(out, ' ')",
        file.display().to_string()
    );
    let kernel = c.ok("lua", json!({ "code": code }));
    let kernel = format!("{} ", kernel.lines().next().unwrap());
    c.finish();

    let rounding = 0.05 + 1e-6;
    let mcp_peak = number_after(&text, "left: peak ").max(number_after(&text, "right: peak "));
    let mix_peak = number_after(&kernel, "peak ");
    assert!((mcp_peak - mix_peak).abs() <= rounding, "{text}\n{kernel}");

    // The MCP gives each octave band relative to the loudest one.
    let octaves = [
        "31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k",
    ];
    let loudest = octaves
        .iter()
        .map(|band| number_after(&kernel, &format!(" {band} ")))
        .fold(f64::MIN, f64::max);
    let spectrum = text
        .lines()
        .find(|l| l.starts_with("spectrum ("))
        .unwrap_or_else(|| panic!("no spectrum in:\n{text}"));
    let spectrum = format!("{spectrum} ");
    for band in octaves {
        let mcp = number_after(&spectrum, &format!(" {band} "));
        let mix = number_after(&kernel, &format!(" {band} ")) - loudest;
        assert!(
            (mcp - mix).abs() <= rounding,
            "band {band}: {mcp} and {mix}\n{text}\n{kernel}"
        );
    }
}
