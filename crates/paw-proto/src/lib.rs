//! The client's side of the kernel's control protocol: one JSON object per
//! line over a Unix socket, or over TCP inside TLS. docs/reference/protocol.md
//! describes it; the server's side is `paw_core::rpc`. Kept apart from the
//! kernel so that a program that only talks to one (the window, a remote
//! terminal) need not be built with it.

pub mod monitor;
pub mod tls;

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, channel};

use anyhow::{Context, Result, anyhow, bail};
use serde_json::{Value, json};

pub use tls::Wire;

/// The protocol's version, told in `hello`: 2 added pushed events,
/// subscriptions, the screen for remote terminals, and TCP; 3 put TCP inside
/// TLS and gave every attached terminal and window a seat of its own.
pub const VERSION: u32 = 3;

/// Where this program keeps what it learns on this machine:
/// `$XDG_STATE_HOME/paw`, by default `~/.local/state/paw`.
pub fn state_dir() -> PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))
        .unwrap_or_else(std::env::temp_dir)
        .join("paw")
}

/// A connection, as the kernel names it. 0 is no connection at all: the
/// program's own terminal, or a call made from inside.
pub type ClientId = u64;

/// What shows that a connection knows `token`, for the server's `nonce`:
/// the SHA-256 of the two, so that the token itself never crosses the wire
/// and an answer overheard is of no use the next time.
pub fn proof(token: &str, nonce: &str) -> String {
    hex(&sha256(format!("{token}:{nonce}").as_bytes()))
}

/// Bytes as lowercase hexadecimal digits: the `hex` crate's, the one
/// function for this in paw (`hex::encode_upper` where a format wants
/// capitals).
pub use hex::encode as hex;

/// A connection to a kernel, for programs that talk to one: `paw ctl`,
/// `paw attach`, the window. Replies come back from [`call`](Self::call);
/// what the kernel pushes waits in [`events`](Self::events).
pub struct Connection {
    writer: Box<dyn Write + Send>,
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
        let stream = UnixStream::connect(path)
            .with_context(|| format!("no running instance at {}", path.display()))?;
        let reader = stream.try_clone()?;
        Self::start(reader, Box::new(stream), None)
    }

    /// Connect to a kernel listening on the network, in TLS, holding it to
    /// the certificate this machine remembers for `address`, and show the
    /// token.
    pub fn tcp(address: &str, token: &str) -> Result<Self> {
        Self::tcp_with(address, token, &Wire::default())
    }

    /// Connect to a kernel listening on the network, the way `wire` says.
    pub fn tcp_with(address: &str, token: &str, wire: &Wire) -> Result<Self> {
        let resolved = address
            .to_socket_addrs()
            .with_context(|| format!("`{address}` is not an address: host:port"))?
            .next()
            .with_context(|| format!("`{address}` names no address"))?;
        let stream = TcpStream::connect_timeout(&resolved, std::time::Duration::from_secs(10))
            .with_context(|| format!("no running instance at {address}"))?;
        let _ = stream.set_nodelay(true);
        match wire {
            Wire::Plain => {
                let reader = stream.try_clone()?;
                Self::start(reader, Box::new(stream), Some(token))
            }
            Wire::Tls { known, accept_new } => {
                // The handshake may not take for ever; afterwards, reading
                // waits as long as the kernel is quiet.
                stream.set_read_timeout(Some(std::time::Duration::from_secs(10)))?;
                let probe = stream.try_clone()?;
                let opened = tls::connect(address, stream, known, *accept_new)?;
                probe.set_read_timeout(None)?;
                let mut connection =
                    Self::start(opened.reader, Box::new(opened.writer), Some(token))?;
                connection.trusted_now = opened.trusted_now;
                Ok(connection)
            }
        }
    }

    fn start(
        reader: impl Read + Send + 'static,
        writer: Box<dyn Write + Send>,
        token: Option<&str>,
    ) -> Result<Self> {
        let (reply_tx, replies) = channel();
        let (event_tx, events) = channel();
        std::thread::spawn(move || {
            for line in BufReader::new(reader).lines() {
                let Ok(line) = line else { break };
                let Ok(message) = serde_json::from_str::<Value>(&line) else {
                    continue;
                };
                let sent = match message["event"].as_str() {
                    Some(name) => event_tx
                        .send((name.to_string(), message["payload"].clone()))
                        .is_ok(),
                    None => reply_tx.send(message).is_ok(),
                };
                if !sent {
                    break;
                }
            }
        });
        let mut connection = Self {
            writer,
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
                    .recv_timeout(std::time::Duration::from_secs(10))
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
        writeln!(
            self.writer,
            "{}",
            json!({ "id": null, "method": method, "params": params })
        )?;
        self.writer.flush()?;
        Ok(())
    }

    /// Call a method and wait for the answer.
    pub fn call(&mut self, method: &str, params: Value) -> Result<Value> {
        self.next += 1;
        let id = self.next;
        writeln!(
            self.writer,
            "{}",
            json!({ "id": id, "method": method, "params": params })
        )
        .map_err(|_| anyhow!("the kernel went away"))?;
        self.writer
            .flush()
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
            hex(&sha256(b"")),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            hex(&sha256(b"abc")),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            hex(&sha256(
                b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
            )),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
        // A message that fills its last block to the byte before the length.
        assert_eq!(
            hex(&sha256(&[b'a'; 119])),
            "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb"
        );
    }

    #[test]
    fn a_proof_is_of_one_token_and_one_nonce() {
        let a = proof("0123456789abcdef", "n1");
        assert_eq!(a.len(), 64);
        assert_ne!(a, proof("0123456789abcdef", "n2"));
        assert_ne!(a, proof("0123456789abcdeX", "n1"));
    }
}
