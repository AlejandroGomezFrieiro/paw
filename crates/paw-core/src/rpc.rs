//! The control socket: other processes, on this machine or another, call
//! into a running kernel and hear from it, one JSON object per line.
//!
//! Request: `{"id": 1, "method": "eval", "params": ["return paw.transport.position"]}`
//! Reply: `{"id": 1, "result": 3.5}` or `{"id": 1, "error": "..."}`
//! Pushed: `{"event": "transport.play", "payload": {"position": 0}}`
//!
//! A connection only hears what it asked for (`subscribe`, `frontend.watch`,
//! `ui.attach`: see docs/reference/protocol.md). Replies and events go out through one
//! queue per connection, in the order they were made.
//!
//! Two ways in: a Unix socket, which whoever may open the file may use, and
//! TCP, inside TLS (see `crate::tls`), where a connection first has to show
//! that it knows the token without sending it (`hello`). TCP in the clear
//! is only there when asked for, for a network you trust.
//!
//! Every connection is two tasks on one tokio runtime, on a thread of its
//! own (see [`runtime`]): one reads requests and hands them to the kernel's
//! channel, the other writes what the kernel queued. The kernel's Lua loop
//! never waits on them.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex, OnceLock};

use anyhow::{Context, Result, bail};
pub use paw_proto::tls::known_path;
pub use paw_proto::{ClientId, Connection, VERSION, Wire, proof, sha256};
use paw_proto::hex;
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream, UnixListener};
use tokio::runtime::Handle;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::timeout;

use crate::kernel::KernelMsg;

/// How much may wait to be written to one connection. One that does not
/// read what it asked for (a program that stopped, a network that went
/// away without saying) is closed when this much is waiting for it,
/// instead of being kept for in memory without end.
const MAX_WAITING: usize = 32 << 20;

/// The longest request listened to: from a connection that has shown the
/// token (or needs none), and from one that has not yet.
const MAX_REQUEST: u64 = 64 << 20;
const MAX_HELLO: u64 = 4096;

/// How long a network connection has for the TLS handshake, and for each
/// line it sends until it has shown the token.
const HELLO_TIME: std::time::Duration = std::time::Duration::from_secs(10);

/// How long a connection to a TLS port may stay quiet before it is taken
/// for a client that waits to be greeted in the clear, as those from before
/// TLS do. A TLS client speaks at once.
const PLAIN_WAIT: std::time::Duration = std::time::Duration::from_millis(1500);

/// What a client that does not speak TLS is told by a port that only does.
const TLS_ONLY: &str = "this instance takes network connections in TLS only (protocol 3): \
    connect with a paw as new as it, or start the instance with --no-tls";

/// Where the kernel puts its answer to one call.
pub type Reply = oneshot::Sender<Result<Value, String>>;

/// The runtime every connection runs on: a current-thread runtime on one
/// thread of its own, made when the first listener opens. It sleeps while
/// no socket has anything to say and no time limit runs. I/O only: calls
/// go to the kernel's channel, as they did from the threads before.
fn runtime() -> Result<&'static Handle> {
    static RUNTIME: OnceLock<Handle> = OnceLock::new();
    static MAKING: Mutex<()> = Mutex::new(());
    let _one_at_a_time = MAKING.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(handle) = RUNTIME.get() {
        return Ok(handle);
    }
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .context("starting the I/O of the control socket")?;
    let handle = runtime.handle().clone();
    std::thread::Builder::new()
        .name("paw-rpc".into())
        .spawn(move || runtime.block_on(std::future::pending::<()>()))
        .context("starting the thread of the control socket")?;
    Ok(RUNTIME.get_or_init(|| handle))
}

/// One connection's way out.
struct Out {
    lines: mpsc::UnboundedSender<String>,
    /// The bytes queued and not yet written.
    waiting: Arc<AtomicUsize>,
    /// Ends the connection from this side.
    close: watch::Sender<bool>,
}

/// Every open connection's way out. Cheap to clone; the kernel keeps one to
/// push events with.
#[derive(Clone, Default)]
pub struct Clients {
    out: Arc<Mutex<HashMap<ClientId, Out>>>,
    next: Arc<AtomicU64>,
}

impl Clients {
    fn add(&self, out: Out) -> ClientId {
        let id = self.next.fetch_add(1, Ordering::Relaxed) + 1;
        self.out.lock().unwrap().insert(id, out);
        id
    }

    fn remove(&self, id: ClientId) {
        self.out.lock().unwrap().remove(&id);
    }

    /// Queue a line for a connection. False when it is gone, or when it has
    /// let too much wait and is closed for it.
    pub fn send(&self, id: ClientId, line: String) -> bool {
        let mut all = self.out.lock().unwrap();
        let Some(out) = all.get(&id) else {
            return false;
        };
        let length = line.len();
        let waiting = out.waiting.fetch_add(length, Ordering::Relaxed) + length;
        if waiting > MAX_WAITING || out.lines.send(line).is_err() {
            out.close.send_replace(true);
            all.remove(&id);
            return false;
        }
        true
    }

    /// Push an event to a connection. False when it is gone.
    pub fn push(&self, id: ClientId, event: &str, payload: &Value) -> bool {
        self.send(id, json!({ "event": event, "payload": payload }).to_string())
    }

    /// The connections that are open.
    pub fn ids(&self) -> Vec<ClientId> {
        let mut ids: Vec<ClientId> = self.out.lock().unwrap().keys().copied().collect();
        ids.sort_unstable();
        ids
    }
}

/// Removes the socket file when the server goes away.
pub struct Server {
    path: PathBuf,
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

/// Where the control socket lives unless told otherwise.
pub fn default_path() -> PathBuf {
    let dir = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    dir.join("paw.sock")
}

/// Listen on `path` and forward calls to the kernel.
pub fn serve(path: &Path, kernel: Sender<KernelMsg>, clients: Clients) -> Result<Server> {
    if path.exists() {
        if UnixStream::connect(path).is_ok() {
            bail!(
                "another instance is already listening on {}",
                path.display()
            );
        }
        // Left behind by an instance that did not shut down cleanly.
        std::fs::remove_file(path)?;
    }
    let listener = std::os::unix::net::UnixListener::bind(path)
        .with_context(|| format!("listening on {}", path.display()))?;
    listener.set_nonblocking(true)?;
    let runtime = runtime()?;
    let listener = {
        let _inside = runtime.enter();
        UnixListener::from_std(listener)?
    };
    runtime.spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                continue;
            };
            let (reader, writer) = stream.into_split();
            tokio::spawn(connection(reader, writer, kernel.clone(), clients.clone(), None));
        }
    });
    Ok(Server {
        path: path.to_path_buf(),
    })
}

/// Listen on a TCP address (`127.0.0.1:7700`, `0.0.0.0:7700`) for
/// connections that know `token`: in TLS with `tls`, else in the clear.
/// Returns the address bound, which says which port was given when the
/// address asked for port 0.
pub fn serve_tcp(
    address: &str,
    token: String,
    tls: Option<Arc<rustls::ServerConfig>>,
    kernel: Sender<KernelMsg>,
    clients: Clients,
) -> Result<std::net::SocketAddr> {
    if token.len() < 16 {
        bail!("the token for network connections is too short to be one: 16 characters at least");
    }
    let listener =
        std::net::TcpListener::bind(address).with_context(|| format!("listening on {address}"))?;
    let bound = listener.local_addr()?;
    listener.set_nonblocking(true)?;
    let runtime = runtime()?;
    let listener = {
        let _inside = runtime.enter();
        TcpListener::from_std(listener)?
    };
    let tls = tls.map(tokio_rustls::TlsAcceptor::from);
    runtime.spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                continue;
            };
            let (kernel, clients, token) = (kernel.clone(), clients.clone(), token.clone());
            tokio::spawn(network(stream, tls.clone(), kernel, clients, token));
        }
    });
    Ok(bound)
}

/// Serve one network connection: in TLS when the port takes TLS, else in
/// the clear.
async fn network(
    stream: TcpStream,
    tls: Option<tokio_rustls::TlsAcceptor>,
    kernel: Sender<KernelMsg>,
    clients: Clients,
    token: String,
) {
    // Small messages both ways: do not wait to fill a packet.
    let _ = stream.set_nodelay(true);
    let Some(acceptor) = tls else {
        let (reader, writer) = stream.into_split();
        return connection(reader, writer, kernel, clients, Some(token)).await;
    };
    // A TLS client opens with a handshake record; anything else is told
    // what this port wants.
    if first_byte(&stream).await != Some(0x16) {
        return refuse_plain(stream).await;
    }
    // Whoever connects and says nothing does not keep a task.
    if let Ok(Ok(stream)) = timeout(HELLO_TIME, acceptor.accept(stream)).await {
        let (reader, writer) = tokio::io::split(stream);
        connection(reader, writer, kernel, clients, Some(token)).await;
    }
}

/// The first byte a new connection sends, or nothing when it waits to be
/// spoken to first (or goes away).
async fn first_byte(stream: &TcpStream) -> Option<u8> {
    let mut byte = [0u8; 1];
    let seen = matches!(timeout(PLAIN_WAIT, stream.peek(&mut byte)).await, Ok(Ok(1)));
    seen.then_some(byte[0])
}

/// Tell a client that speaks in the clear, on a port that only takes TLS,
/// why it will not be listened to: in the greeting it waits for, and in
/// the answer to its first request.
async fn refuse_plain(mut stream: TcpStream) {
    let hello = json!({ "event": "hello", "payload": { "version": VERSION, "error": TLS_ONLY } });
    if stream.write_all(format!("{hello}\n").as_bytes()).await.is_err() {
        return;
    }
    let mut line = Vec::new();
    let mut reader = BufReader::new((&mut stream).take(MAX_HELLO));
    if let Ok(Ok(_)) = timeout(HELLO_TIME, reader.read_until(b'\n', &mut line)).await
        && let Ok(request) = serde_json::from_slice::<Value>(&line)
    {
        let error = json!({ "id": request["id"], "error": TLS_ONLY });
        let _ = stream.write_all(format!("{error}\n").as_bytes()).await;
    }
    let _ = stream.shutdown().await;
}

/// Where the token for network connections is kept on this machine:
/// `$XDG_STATE_HOME/paw/token`.
pub fn token_path() -> PathBuf {
    paw_proto::state_dir().join("token")
}

/// The token in `path`, made and written there (readable by its owner
/// alone) if there is none yet.
pub fn token_at(path: &Path) -> Result<String> {
    if let Ok(text) = std::fs::read_to_string(path) {
        let token = text.trim().to_string();
        if token.len() >= 16 {
            return Ok(token);
        }
    }
    use std::os::unix::fs::OpenOptionsExt;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
    }
    let token = new_token();
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
        .with_context(|| format!("writing {}", path.display()))?;
    writeln!(file, "{token}")?;
    Ok(token)
}

/// What a connection that has to show it knows the token is sent first,
/// and what it must answer with: see [`proof`].
fn nonce() -> String {
    let mut bytes = [0u8; 16];
    let read = std::fs::File::open("/dev/urandom").and_then(|mut f| f.read_exact(&mut bytes));
    if read.is_err() {
        // No random device: the time and a counter still differ every time.
        static COUNT: AtomicU64 = AtomicU64::new(0);
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos());
        let seed = format!("{now}:{}", COUNT.fetch_add(1, Ordering::Relaxed));
        bytes.copy_from_slice(&sha256(seed.as_bytes())[..16]);
    }
    hex(&bytes)
}

/// A new token for network connections: 32 random hexadecimal digits.
pub fn new_token() -> String {
    nonce()
}

/// Compare without stopping at the first difference.
fn same(a: &str, b: &str) -> bool {
    a.len() == b.len()
        && a.bytes()
            .zip(b.bytes())
            .fold(0u8, |diff, (x, y)| diff | (x ^ y))
            == 0
}

/// Waits until the kernel's side closes the connection (see
/// [`Clients::send`]). Never ends when the connection ends by itself.
async fn closed(mut close: watch::Receiver<bool>) {
    if close.wait_for(|&closed| closed).await.is_err() {
        std::future::pending::<()>().await;
    }
}

/// Write what the kernel queued for a connection, in order, until the
/// queue ends (after the lines already in it) or a write fails.
async fn write_out(
    mut writer: impl AsyncWrite + Unpin,
    mut queue: mpsc::UnboundedReceiver<String>,
    written: Arc<AtomicUsize>,
) {
    while let Some(line) = queue.recv().await {
        let sent = writer.write_all(line.as_bytes()).await.is_ok()
            && writer.write_all(b"\n").await.is_ok()
            && writer.flush().await.is_ok();
        written.fetch_sub(line.len(), Ordering::Relaxed);
        if !sent {
            break;
        }
    }
}

/// Serve one connection until it closes, from either side: its requests
/// go to the kernel in order, and whatever the kernel has for it goes out
/// through `writer`.
async fn connection(
    reader: impl AsyncRead + Unpin,
    writer: impl AsyncWrite + Unpin + Send + 'static,
    kernel: Sender<KernelMsg>,
    clients: Clients,
    token: Option<String>,
) {
    let (lines, queue) = mpsc::unbounded_channel();
    let (close, close_seen) = watch::channel(false);
    let waiting = Arc::new(AtomicUsize::new(0));
    let writing = write_out(writer, queue, waiting.clone());
    let stop_writing = closed(close_seen.clone());
    tokio::spawn(async move {
        tokio::select! {
            () = writing => {}
            () = stop_writing => {}
        }
    });
    let id = clients.add(Out {
        lines,
        waiting,
        close,
    });
    tokio::select! {
        () = requests(id, reader, &kernel, &clients, token) => {}
        () = closed(close_seen) => {}
    }
    clients.remove(id);
    let _ = kernel.send(KernelMsg::Gone(id));
}

/// Read a connection's requests and answer each in turn, until it closes,
/// says what cannot be listened to, or fails to show the token.
async fn requests(
    id: ClientId,
    reader: impl AsyncRead + Unpin,
    kernel: &Sender<KernelMsg>,
    clients: &Clients,
    token: Option<String>,
) {
    // Everything for this connection goes through its queue, counted.
    let out = |line: String| clients.send(id, line);
    // Over the network, nothing is listened to before the token is shown.
    let challenge = token.as_ref().map(|_| nonce());
    let mut trusted = token.is_none();
    if let Some(nonce) = &challenge {
        out(json!({ "event": "hello", "payload": { "version": VERSION, "nonce": nonce } })
            .to_string());
    }
    let mut reader = BufReader::new(reader);
    loop {
        // One line, and no more of it than a request may be long: what
        // has not shown the token gets to say very little, in HELLO_TIME.
        let limit = if trusted { MAX_REQUEST } else { MAX_HELLO };
        let mut bytes = Vec::new();
        let mut limited = (&mut reader).take(limit + 1);
        let read = limited.read_until(b'\n', &mut bytes);
        let read = if trusted {
            read.await
        } else {
            timeout(HELLO_TIME, read).await.unwrap_or(Ok(0))
        };
        if matches!(read, Ok(0) | Err(_)) {
            break;
        }
        if bytes.last() != Some(&b'\n') && bytes.len() as u64 > limit {
            out(json!({ "id": null, "error": "the request is too long" }).to_string());
            break;
        }
        let line = String::from_utf8_lossy(&bytes);
        if line.trim().is_empty() {
            continue;
        }
        let request = match serde_json::from_str::<Value>(&line) {
            Ok(request) => request,
            Err(err) => {
                out(json!({ "id": null, "error": format!("bad request: {err}") }).to_string());
                if !trusted {
                    break;
                }
                continue;
            }
        };
        let request_id = request["id"].clone();
        let method = request["method"].as_str().unwrap_or_default().to_string();
        let params = request.get("params").cloned().unwrap_or(json!([]));
        let outcome = if method == "hello" {
            // Who is there, and (over the network) the proof.
            let shown = params[0]["proof"].as_str().or(params["proof"].as_str());
            if let (Some(token), Some(nonce)) = (&token, &challenge) {
                trusted = shown.is_some_and(|shown| same(shown, &proof(token, nonce)));
            }
            if trusted {
                Ok(json!({ "version": VERSION, "client": id }))
            } else {
                Err("the token is not the right one".to_string())
            }
        } else if !trusted {
            Err("say `hello` with the proof of the token first".to_string())
        } else {
            let (reply, result) = oneshot::channel();
            let sent = kernel.send(KernelMsg::Rpc {
                client: id,
                method,
                params,
                reply,
            });
            if sent.is_err() {
                break;
            }
            result
                .await
                .unwrap_or_else(|_| Err("the kernel went away".to_string()))
        };
        let response = match outcome {
            Ok(result) => json!({ "id": request_id, "result": result }),
            Err(error) => json!({ "id": request_id, "error": error }),
        };
        if !out(response.to_string()) {
            break;
        }
        if !trusted {
            // One try: a wrong token ends the connection.
            break;
        }
    }
}

/// Call a method on a running instance and wait for the answer.
pub fn call(path: &Path, method: &str, params: Value) -> Result<Value> {
    Connection::unix(path)?.call(method, params)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_are_long_differ_and_compare_whole() {
        assert_ne!(new_token(), new_token());
        assert_eq!(new_token().len(), 32);
        let a = proof("0123456789abcdef", "n1");
        assert!(same(&a, &proof("0123456789abcdef", "n1")));
        assert!(!same(&a, &a[..63]));
        assert!(!same(&a, &proof("0123456789abcdef", "n2")));
    }
}
