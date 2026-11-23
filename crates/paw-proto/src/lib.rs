//! The client's side of the kernel's control protocol: one JSON object per
//! line over a Unix socket, or over TCP inside TLS. docs/reference/protocol.md
//! describes it; the server's side is `paw_core::rpc`. Kept apart from the
//! kernel so that a program that only talks to one (the window, a remote
//! terminal) need not be built with it.
//!
//! The I/O runs on one tokio runtime for the process (`runtime`), and
//! [`Connection`] is a blocking facade over it: a call waits for its
//! answer, and what the kernel pushes waits in a channel until it is taken.

pub mod dirs;
pub mod monitor;
pub mod runtime;
pub mod tls;

use std::io::Read;
use std::net::{SocketAddr, ToSocketAddrs};
use std::path::Path;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::net::{TcpStream, UnixStream};
use tokio::task::AbortHandle;
use tokio::time::timeout;

pub use tls::Wire;

/// How long connecting over the network, the TLS handshake, and waiting
/// for the kernel's `hello` may each take.
const HELLO_TIME: Duration = Duration::from_secs(10);

/// The protocol's version, told in `hello`: 2 added pushed events,
/// subscriptions, the screen for remote terminals, and TCP; 3 put TCP inside
/// TLS and gave every attached terminal and window a seat of its own.
pub const VERSION: u32 = 3;

/// A connection, as the kernel names it. 0 is no connection at all: the
/// program's own terminal, or a call made from inside.
pub type ClientId = u64;

/// What shows that a connection knows `token`, for the server's `nonce`:
/// the SHA-256 of the two, so that the token itself never crosses the wire
/// and an answer overheard is of no use the next time.
pub fn proof(token: &str, nonce: &str) -> String {
    hex::encode(sha256(format!("{token}:{nonce}").as_bytes()))
}

/// A connection to a kernel, for programs that talk to one: `paw ctl`,
/// `paw attach`, the window. Replies come back from [`call`](Self::call);
/// what the kernel pushes waits in [`events`](Self::events).
pub struct Connection {
    /// The way out, written from the caller's thread on the runtime.
    writer: Box<dyn AsyncWrite + Send + Unpin>,
    /// The task that reads, ended when the connection is dropped.
    reading: AbortHandle,
    replies: Receiver<Value>,
    pub events: Receiver<(String, Value)>,
    next: u64,
    /// The connection's number at the kernel, from `hello`.
    pub client: ClientId,
    /// The fingerprint of the instance's certificate, when this connection
    /// remembered it for the first time (or in place of another).
    pub trusted_now: Option<String>,
}

impl Connection {
    /// Connect to the kernel listening on a Unix socket.
    pub fn unix(path: &Path) -> Result<Self> {
        let runtime = runtime::handle()?;
        let stream = runtime
            .block_on(UnixStream::connect(path))
            .with_context(|| format!("no running instance at {}", path.display()))?;
        let (reader, writer) = stream.into_split();
        Self::start(reader, Box::new(writer), None)
    }

    /// Connect to a kernel listening on the network, the way `wire` says.
    pub fn tcp_with(address: &str, token: &str, wire: &Wire) -> Result<Self> {
        let resolved = address
            .to_socket_addrs()
            .with_context(|| format!("`{address}` is not an address: host:port"))?
            .next()
            .with_context(|| format!("`{address}` names no address"))?;
        let runtime = runtime::handle()?;
        let stream = runtime.block_on(tcp_connect(resolved, address))?;
        match wire {
            Wire::Plain => {
                let (reader, writer) = stream.into_split();
                Self::start(reader, Box::new(writer), Some(token))
            }
            Wire::Tls { known, accept_new } => {
                let opened = runtime.block_on(tls::connect(address, stream, known, *accept_new))?;
                let (reader, writer) = tokio::io::split(opened.stream);
                let mut connection = Self::start(reader, Box::new(writer), Some(token))?;
                connection.trusted_now = opened.trusted_now;
                Ok(connection)
            }
        }
    }

    fn start(
        reader: impl AsyncRead + Send + Unpin + 'static,
        writer: Box<dyn AsyncWrite + Send + Unpin>,
        token: Option<&str>,
    ) -> Result<Self> {
        let (reply_tx, replies) = channel();
        let (event_tx, events) = channel();
        let reading = runtime::handle()?.spawn(read(reader, reply_tx, event_tx)).abort_handle();
        let mut connection = Self {
            writer,
            reading,
            replies,
            events,
            next: 0,
            client: 0,
            trusted_now: None,
        };
        let params = match token {
            Some(token) => {
                // The kernel speaks first over the network: what to prove.
                let (name, payload) = connection
                    .events
                    .recv_timeout(HELLO_TIME)
                    .map_err(|_| anyhow!("the kernel did not say hello"))?;
                // An instance that will not talk this way says why.
                if let Some(error) = payload["error"].as_str().filter(|_| name == "hello") {
                    bail!("{error}");
                }
                let nonce = payload["nonce"].as_str().filter(|_| name == "hello");
                let nonce = nonce.context("the kernel did not say hello")?;
                json!([{ "proof": proof(token, nonce) }])
            }
            None => json!([{}]),
        };
        // A kernel from before `hello` existed answers with an error:
        // it is one that only takes calls, which is all `call` needs.
        if let Ok(hello) = connection.call("hello", params) {
            connection.client = hello["client"].as_u64().unwrap_or(0);
        } else if token.is_some() {
            bail!("the kernel did not accept the token");
        }
        Ok(connection)
    }

    /// Send a request without waiting for its answer, which is dropped.
    pub fn notify(&mut self, method: &str, params: Value) -> Result<()> {
        self.send(&json!({ "id": null, "method": method, "params": params }))?;
        Ok(())
    }

    /// Call a method and wait for the answer.
    pub fn call(&mut self, method: &str, params: Value) -> Result<Value> {
        self.next += 1;
        let id = self.next;
        self.send(&json!({ "id": id, "method": method, "params": params }))
            .map_err(|_| anyhow!("the kernel went away"))?;
        loop {
            let response = self
                .replies
                .recv()
                .map_err(|_| anyhow!("the kernel went away"))?;
            // Answers to requests nobody waits for are passed over.
            if response["id"].as_u64() != Some(id) {
                continue;
            }
            return match response.get("error").and_then(Value::as_str) {
                Some(error) => Err(anyhow!("{error}")),
                None => Ok(response["result"].clone()),
            };
        }
    }
}

impl Connection {
    /// Write one message, a line of JSON, and wait until it is sent.
    fn send(&mut self, message: &Value) -> std::io::Result<()> {
        let line = format!("{message}\n");
        let runtime = runtime::handle().map_err(std::io::Error::other)?;
        runtime.block_on(async {
            self.writer.write_all(line.as_bytes()).await?;
            self.writer.flush().await
        })
    }
}

impl Drop for Connection {
    /// The reading task lets go of the socket too, so the kernel sees the
    /// connection end now, not when it next sends something.
    fn drop(&mut self) {
        self.reading.abort();
    }
}

/// Read what the kernel sends, one JSON object per line: answers go to
/// `replies`, pushed events to `events`, in the order they came. Ends with
/// the connection, or when nobody listens any more.
async fn read(
    reader: impl AsyncRead + Unpin,
    replies: Sender<Value>,
    events: Sender<(String, Value)>,
) {
    let mut lines = BufReader::new(reader).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let sent = match message["event"].as_str() {
            Some(name) => events.send((name.to_string(), message["payload"].clone())).is_ok(),
            None => replies.send(message).is_ok(),
        };
        if !sent {
            break;
        }
    }
}

/// Connect to `resolved`, which `address` names, within [`HELLO_TIME`].
async fn tcp_connect(resolved: SocketAddr, address: &str) -> Result<TcpStream> {
    let stream = match timeout(HELLO_TIME, TcpStream::connect(resolved)).await {
        Ok(connected) => connected,
        Err(_) => Err(std::io::ErrorKind::TimedOut.into()),
    }
    .with_context(|| format!("no running instance at {address}"))?;
    // Small messages both ways: do not wait to fill a packet.
    let _ = stream.set_nodelay(true);
    Ok(stream)
}

/// How much of a file goes in one `file.chunk`.
const CHUNK: usize = 1 << 20;

impl Connection {
    /// Send a file on this machine to the instance, into its project's
    /// media folder, a piece at a time. Returns the file's path there.
    pub fn send_file(&mut self, path: &Path) -> Result<String> {
        use base64::Engine;
        let mut file = std::fs::File::open(path).with_context(|| format!("reading {}", path.display()))?;
        let size = file.metadata()?.len();
        let name = path.file_name().context("not a file")?.to_string_lossy();
        let id = self.call("file.begin", json!([{ "name": name, "size": size }]))?;
        let mut buf = vec![0u8; CHUNK];
        let sent = (|| -> Result<String> {
            loop {
                let n = file.read(&mut buf)?;
                if n == 0 {
                    break;
                }
                let text = base64::engine::general_purpose::STANDARD.encode(&buf[..n]);
                self.call("file.chunk", json!([id, text]))?;
            }
            let there = self.call("file.end", json!([id]))?;
            there.as_str().map(str::to_string).context("the instance did not say where it put the file")
        })();
        if sent.is_err() {
            let _ = self.notify("file.abort", json!([id]));
        }
        sent
    }

    /// Send a sound file to the instance and bring it into the project on
    /// a new track, as `:import` does there. Returns its path there.
    pub fn send_and_import(&mut self, path: &Path) -> Result<String> {
        let there = self.send_file(path)?;
        self.call("eval", json!(["paw.commands.run('import', { ... })", there]))?;
        Ok(there)
    }
}

/// Call a method on the instance listening on a Unix socket and wait for
/// the answer.
pub fn call(path: &Path, method: &str, params: Value) -> Result<Value> {
    Connection::unix(path)?.call(method, params)
}

/// SHA-256 (FIPS 180-4), for [`proof`] and the certificates'
/// fingerprints: `ring`'s, which TLS links already.
pub fn sha256(data: &[u8]) -> [u8; 32] {
    let digest = ring::digest::digest(&ring::digest::SHA256, data);
    let mut out = [0u8; 32];
    out.copy_from_slice(digest.as_ref());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_gives_the_published_digests() {
        assert_eq!(
            hex::encode(sha256(b"")),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            hex::encode(sha256(b"abc")),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            hex::encode(sha256(
                b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
            )),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
        // A message that fills its last block to the byte before the length.
        assert_eq!(
            hex::encode(sha256(&[b'a'; 119])),
            "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb"
        );
    }

    use std::sync::{Arc, Mutex};

    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, DuplexStream};

    /// The token and nonce of the kernel in memory, so that the proof is
    /// the same in each run.
    const TOKEN: &str = "0123456789abcdef";
    const NONCE: &str = "6e6f6e6365";

    /// What the kernel in memory replies to a request: the reply's fields
    /// after `id`, and an event that it pushes after the reply.
    fn answer(method: &str) -> (Value, Option<Value>) {
        match method {
            "hello" => (json!({ "result": { "version": VERSION, "client": 7 } }), None),
            "subscribe" => (
                json!({ "result": ["transport.*"] }),
                Some(json!({ "event": "transport.play", "payload": { "position": 0 } })),
            ),
            "file.begin" => (json!({ "result": 1 }), None),
            "file.chunk" => (json!({ "result": 10 }), None),
            "file.end" => (json!({ "result": "media/take.wav" }), None),
            "eval" => (json!({ "result": null }), None),
            other => (json!({ "error": format!("no method `{other}`") }), None),
        }
    }

    /// A kernel in memory at the other end of `stream`, as over the network:
    /// it says hello first, then answers each request with [`answer`]. Each
    /// line it reads goes into `transcript` after `>`, and each line it
    /// writes after `<`, in the order of the wire. It records what it sends
    /// before it sends it, so the transcript is whole when the client has
    /// the reply.
    async fn kernel(stream: DuplexStream, transcript: Arc<Mutex<Vec<String>>>) {
        let (reader, mut writer) = tokio::io::split(stream);
        let mut lines = BufReader::new(reader).lines();
        let hello = json!({ "event": "hello", "payload": { "version": VERSION, "nonce": NONCE } });
        let mut out = vec![hello];
        loop {
            let text: String = out.iter().map(|message| format!("{message}\n")).collect();
            transcript.lock().unwrap().extend(out.iter().map(|message| format!("< {message}")));
            writer.write_all(text.as_bytes()).await.unwrap();
            let Ok(Some(line)) = lines.next_line().await else { break };
            transcript.lock().unwrap().push(format!("> {line}"));
            let request: Value = serde_json::from_str(&line).unwrap();
            let (mut reply, event) = answer(request["method"].as_str().unwrap());
            out.clear();
            // A request with no id needs no reply.
            if !request["id"].is_null() {
                reply["id"] = request["id"].clone();
                out.push(reply);
            }
            out.extend(event);
        }
    }

    #[test]
    fn the_client_speaks_the_protocol_as_the_golden_file_has_it() {
        let transcript = Arc::new(Mutex::new(Vec::new()));
        let (client, far) = tokio::io::duplex(1 << 16);
        let runtime = runtime::handle().unwrap();
        runtime.spawn(kernel(far, Arc::clone(&transcript)));
        let (reader, writer) = tokio::io::split(client);
        let mut connection = Connection::start(reader, Box::new(writer), Some(TOKEN)).unwrap();
        // What the client makes of each reply goes after `=`.
        let got = |line: String| transcript.lock().unwrap().push(format!("= {line}"));
        got(format!("client {}", connection.client));
        got(format!("{}", connection.call("subscribe", json!(["transport.*"])).unwrap()));
        let (event, payload) = connection.events.recv().unwrap();
        got(format!("event {event} {payload}"));
        connection.notify("keys", json!(["gg"])).unwrap();
        got(format!("{:#}", connection.call("nonsense", json!([])).unwrap_err()));
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("take.wav");
        std::fs::write(&file, b"0123456789").unwrap();
        got(connection.send_and_import(&file).unwrap());
        drop(connection);
        insta::assert_snapshot!(transcript.lock().unwrap().join("\n"));
    }

    #[test]
    fn a_proof_is_of_one_token_and_one_nonce() {
        let a = proof("0123456789abcdef", "n1");
        assert_eq!(a.len(), 64);
        assert_ne!(a, proof("0123456789abcdef", "n2"));
        assert_ne!(a, proof("0123456789abcdeX", "n1"));
    }
}
