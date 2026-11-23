//! The tests of chain-lsp through its LSP messages. A client talks to the
//! server over an in-memory connection, in this process. Each wait is for a
//! message. tests/guide.rs runs the binary on its standard input and output.

mod session;

use std::thread::JoinHandle;

use chain_lsp::{Options, SchemaSource, serve};
use lsp_server::{Connection, Message, Notification, Request, RequestId};
use serde_json::{Value, json};

/// The schema of the example host in `tests/fixtures`.
pub const SCHEMA: &str = include_str!("../fixtures/schema.json");

/// The URI of the text that the tests open.
pub const URI: &str = "file:///project/bus.chain";

/// A client of a server that runs on a thread of this process.
pub struct Client {
    connection: Connection,
    server: Option<JoinHandle<()>>,
    next_id: i32,
    /// The `initialize` result.
    pub initialized: Value,
    /// The `window/showMessage` texts that came before the first answer
    /// after `initialize`.
    pub messages: Vec<String>,
}

impl Client {
    /// A server started with `options`, and initialized with
    /// `initialization_options`.
    pub fn start(options: Options, initialization_options: Value) -> Self {
        let (server_side, connection) = Connection::memory();
        let server =
            std::thread::spawn(move || serve(&server_side, &options).expect("the server serves"));
        let mut client = Self {
            connection,
            server: Some(server),
            next_id: 0,
            initialized: Value::Null,
            messages: Vec::new(),
        };
        let params = json!({ "capabilities": {}, "initializationOptions": initialization_options });
        client.initialized = client.request("initialize", params);
        client.notify("initialized", json!({}));
        client
    }

    /// A server with the example schema from a file given on its command line.
    pub fn with_schema_file(dir: &std::path::Path) -> Self {
        let path = dir.join("schema.json");
        std::fs::write(&path, SCHEMA).expect("the schema file is written");
        Self::start(
            Options {
                schema: Some(SchemaSource::File(path)),
            },
            Value::Null,
        )
    }

    pub fn notify(&self, method: &str, params: Value) {
        let notification = Notification::new(method.into(), params);
        self.connection
            .sender
            .send(notification.into())
            .expect("the server takes the notification");
    }

    /// The result of a request. The notifications that come before it are
    /// kept in `messages` (`window/showMessage`) or dropped.
    pub fn request(&mut self, method: &str, params: Value) -> Value {
        self.next_id += 1;
        let id = RequestId::from(self.next_id);
        let request = Request::new(id.clone(), method.into(), params);
        self.connection
            .sender
            .send(request.into())
            .expect("the server takes the request");
        loop {
            match self.connection.receiver.recv().expect("the server answers") {
                Message::Response(response) if response.id == id => {
                    return match response.response_result {
                        Ok(result) => result,
                        Err(error) => panic!("an error in the answer to {method}: {error:?}"),
                    };
                }
                Message::Notification(notification) => self.keep(notification),
                other => panic!("an unexpected message before the answer to {method}: {other:?}"),
            }
        }
    }

    /// The params of the next notification `method`.
    pub fn next(&mut self, method: &str) -> Value {
        loop {
            match self.connection.receiver.recv().expect("the server sends") {
                Message::Notification(notification) if notification.method == method => {
                    return notification.params;
                }
                Message::Notification(notification) => self.keep(notification),
                other => panic!("an unexpected message before {method}: {other:?}"),
            }
        }
    }

    fn keep(&mut self, notification: Notification) {
        if notification.method == "window/showMessage" {
            self.messages.push(
                notification.params["message"]
                    .as_str()
                    .unwrap_or_default()
                    .to_string(),
            );
        }
    }

    /// Opens `text` at [`URI`], and gives its diagnostics.
    pub fn open(&mut self, text: &str) -> Value {
        let document = json!({ "uri": URI, "languageId": "chain", "version": 1, "text": text });
        self.notify("textDocument/didOpen", json!({ "textDocument": document }));
        self.next("textDocument/publishDiagnostics")
    }

    /// The answer to a request about the place of `$` in `marked`, which
    /// the client opens first without the `$`.
    pub fn at(&mut self, method: &str, marked: &str) -> Value {
        let (line, character) = marked
            .lines()
            .enumerate()
            .find_map(|(line, text)| {
                text.find('$')
                    .map(|at| (line, text[..at].encode_utf16().count()))
            })
            .expect("the text marks the place with `$`");
        self.open(&marked.replacen('$', "", 1));
        let place = json!({ "textDocument": { "uri": URI }, "position": { "line": line, "character": character } });
        self.request(method, place)
    }
}

impl Drop for Client {
    /// Shuts the server down as an editor does, and waits for its thread.
    fn drop(&mut self) {
        if std::thread::panicking() {
            return;
        }
        self.request("shutdown", Value::Null);
        self.notify("exit", Value::Null);
        if let Some(server) = self.server.take() {
            server.join().expect("the server ends after `exit`");
        }
    }
}
