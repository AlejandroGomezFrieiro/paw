//! The connection to paw kernel's control socket: one JSON object per
//! line, `{"id", "method", "params"}` out and `{"id", "result"|"error"}` back.
//!
//! The connection is made when it is first needed and made again after the
//! kernel goes away, so a kernel can be restarted under a running server.
//! With `--spawn` the server starts a kernel of its own and stops it on exit.
//!
//! The socket and the kernel's process are tokio's, on the server's runtime.
//! The tools run on threads of their own (they also measure audio, which is
//! work for the processor) and wait here for each answer: [`Kernel`] is a
//! blocking front to the runtime.

use std::os::fd::AsFd;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use paw_proto::dirs::Dirs;
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};
use tokio::process::{Child, Command};
use tokio::runtime::Handle;

/// Why a call did not produce a result.
#[derive(Debug)]
pub enum CallError {
    /// The kernel ran the call and reported an error: its message.
    Kernel(String),
    /// There is no kernel to talk to, or it went away.
    Unavailable(String),
}

impl std::fmt::Display for CallError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CallError::Kernel(msg) | CallError::Unavailable(msg) => f.write_str(msg),
        }
    }
}

pub struct SpawnOpts {
    pub binary: PathBuf,
    pub project: Option<PathBuf>,
    pub args: Vec<String>,
}

/// An open connection: answers come in on one half, calls go out on the other.
struct Conn {
    reader: BufReader<OwnedReadHalf>,
    writer: OwnedWriteHalf,
}

pub struct Kernel {
    pub socket: PathBuf,
    timeout: Duration,
    /// The runtime the socket and the kernel's process live on.
    runtime: Handle,
    conn: Option<Conn>,
    spawn: Option<SpawnOpts>,
    child: Option<Child>,
    next_id: u64,
    /// Said once in the next result: the kernel was restarted, say.
    pub notice: Option<String>,
}

/// The user's base directories, read from the environment once. This is a
/// program, so it reads them itself.
fn dirs() -> &'static Dirs {
    static DIRS: OnceLock<Dirs> = OnceLock::new();
    DIRS.get_or_init(|| Dirs::from_vars(|name| std::env::var_os(name)))
}

/// Where `paw` listens unless told otherwise, as its clients find it:
/// `$PAW_SOCKET`, else `$XDG_RUNTIME_DIR/paw.sock`.
pub fn default_socket() -> PathBuf {
    std::env::var_os("PAW_SOCKET").map_or_else(|| dirs().listen_socket(), PathBuf::from)
}

/// The `paw` binary: `$PAW_BIN`, the one beside this program, or `paw` on the path.
pub fn default_binary() -> PathBuf {
    let beside = std::env::current_exe()
        .ok()
        .and_then(|exe| Some(exe.parent()?.join("paw")));
    std::env::var_os("PAW_BIN")
        .map(PathBuf::from)
        .or(beside.filter(|path| path.is_file()))
        .unwrap_or_else(|| PathBuf::from("paw"))
}

impl Kernel {
    pub fn attach(socket: PathBuf, timeout: Duration, runtime: Handle) -> Self {
        Self {
            socket,
            timeout,
            runtime,
            conn: None,
            spawn: None,
            child: None,
            next_id: 1,
            notice: None,
        }
    }

    pub fn spawned(opts: SpawnOpts, timeout: Duration, runtime: Handle) -> Self {
        let name = format!("paw-mcp-{}.sock", std::process::id());
        let socket = [
            dirs().runtime.clone(),
            Some(std::env::temp_dir()),
            Some(PathBuf::from("/tmp")),
        ]
        .into_iter()
        .flatten()
        .map(|dir| dir.join(&name))
        // A Unix socket's path must fit in 108 bytes.
        .find(|path| path.as_os_str().len() < 100)
        .unwrap_or_else(|| PathBuf::from("/tmp").join(&name));
        let mut kernel = Self::attach(socket, timeout, runtime);
        kernel.spawn = Some(opts);
        kernel
    }

    pub fn is_spawned(&self) -> bool {
        self.spawn.is_some()
    }

    /// Start the kernel of a `--spawn` server, if it is not running.
    pub fn start(&mut self) -> Result<(), CallError> {
        self.runtime.clone().block_on(self.start_async())
    }

    async fn start_async(&mut self) -> Result<(), CallError> {
        let Some(opts) = &self.spawn else {
            return Ok(());
        };
        if let Some(child) = self.child.as_mut() {
            match child.try_wait() {
                Ok(None) => return Ok(()),
                Ok(Some(status)) => {
                    self.child = None;
                    self.conn = None;
                    self.notice = Some(format!(
                        "The kernel this server started had stopped ({status}); a new one was started with an empty project. Earlier ids and unsaved work are gone."
                    ));
                }
                Err(_) => self.child = None,
            }
        }
        let mut command = Command::new(&opts.binary);
        command
            .arg("--headless")
            .arg("--listen")
            .arg(&self.socket)
            .args(&opts.args)
            .stdin(Stdio::null());
        if let Some(project) = &opts.project {
            command.arg(project);
        }
        // Whatever the kernel prints must not reach stdout, which is the
        // protocol's: send it to stderr.
        let stderr = std::io::stderr().as_fd().try_clone_to_owned();
        command.stdout(stderr.map_or_else(|_| Stdio::null(), Stdio::from));
        // If this server dies without saying goodbye, the kernel goes too.
        // SAFETY: the closure runs in the child between fork and exec, and
        // only calls prctl (through rustix, a bare syscall), which is
        // async-signal-safe.
        unsafe {
            command.pre_exec(|| {
                let _ = rustix::process::set_parent_process_death_signal(Some(
                    rustix::process::Signal::TERM,
                ));
                Ok(())
            });
        }
        let mut child = command.spawn().map_err(|err| {
            CallError::Unavailable(format!(
                "could not start the kernel `{}`: {err}. Build it with `cargo build -p paw-tui`, or say where it is with --paw or PAW_BIN.",
                opts.binary.display()
            ))
        })?;
        // The first start can take a while: it looks through every installed plugin.
        let deadline = Instant::now() + Duration::from_secs(120);
        loop {
            if let Ok(stream) = UnixStream::connect(&self.socket).await {
                self.set_conn(stream)?;
                break;
            }
            if let Ok(Some(status)) = child.try_wait() {
                return Err(CallError::Unavailable(format!(
                    "the kernel stopped before it was ready ({status}); its messages are on this server's stderr"
                )));
            }
            if Instant::now() > deadline {
                let _ = child.kill().await;
                return Err(CallError::Unavailable(
                    "the kernel did not open its socket within 120 s".into(),
                ));
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        self.child = Some(child);
        Ok(())
    }

    fn set_conn(&mut self, stream: UnixStream) -> Result<(), CallError> {
        let (reader, writer) = stream.into_split();
        self.conn = Some(Conn { reader: BufReader::new(reader), writer });
        Ok(())
    }

    fn unavailable(&self, err: impl std::fmt::Display) -> CallError {
        let how = if self.spawn.is_some() {
            "The kernel this server started is gone; the next call starts a new one.".to_string()
        } else {
            format!(
                "Start one with `paw --headless --listen {0}`{1}; this server reconnects on the next call.",
                self.socket.display(),
                if self.socket == default_socket() {
                    " (or run `paw` with its UI, which listens there by default)"
                } else {
                    ""
                }
            )
        };
        CallError::Unavailable(format!(
            "No paw kernel at {}: {err}. {how}",
            self.socket.display()
        ))
    }

    /// Whether the open connection's peer has hung up: a look at the socket
    /// that takes nothing from it and does not wait.
    fn stale(stream: &UnixStream) -> bool {
        use rustix::net::RecvFlags;
        let mut byte = [0u8];
        match rustix::net::recv(stream, &mut byte, RecvFlags::PEEK | RecvFlags::DONTWAIT) {
            Ok((0, _)) => true,
            Ok(_) => false,
            Err(err) => err != rustix::io::Errno::AGAIN,
        }
    }

    async fn connect(&mut self) -> Result<(), CallError> {
        if let Some(conn) = &self.conn
            && !Self::stale(conn.reader.get_ref().as_ref())
        {
            return Ok(());
        }
        self.conn = None;
        if self.spawn.is_some() {
            self.start_async().await?;
            if self.conn.is_some() {
                return Ok(());
            }
        }
        let stream = UnixStream::connect(&self.socket)
            .await
            .map_err(|err| self.unavailable(err))?;
        self.set_conn(stream)
    }

    /// Call a method on the kernel and wait for its answer.
    pub fn call(&mut self, method: &str, params: Value) -> Result<Value, CallError> {
        self.runtime.clone().block_on(self.call_async(method, params))
    }

    async fn call_async(&mut self, method: &str, params: Value) -> Result<Value, CallError> {
        self.connect().await?;
        let id = self.next_id;
        self.next_id += 1;
        let mut line = json!({ "id": id, "method": method, "params": params }).to_string();
        line.push('\n');
        let conn = self.conn.as_mut().expect("connect() leaves a connection");
        if let Err(err) = conn.writer.write_all(line.as_bytes()).await {
            self.conn = None;
            return Err(self.unavailable(err));
        }
        let mut answer = String::new();
        let read = tokio::time::timeout(self.timeout, conn.reader.read_line(&mut answer)).await;
        match read {
            Err(_elapsed) => {
                // The answer may still come, and would then be read as the
                // answer to the next call: start afresh.
                self.conn = None;
                return Err(CallError::Unavailable(format!(
                    "the kernel did not answer within {} s; it may still be working (see --timeout)",
                    self.timeout.as_secs()
                )));
            }
            Ok(Ok(0)) => {
                self.conn = None;
                return Err(self.unavailable(
                    "the kernel went away during the call (it may have crashed, or quit)",
                ));
            }
            Ok(Ok(_)) => {}
            Ok(Err(err)) => {
                self.conn = None;
                return Err(self.unavailable(err));
            }
        }
        let response: Value = serde_json::from_str(&answer)
            .map_err(|err| CallError::Unavailable(format!("bad answer from the kernel: {err}")))?;
        match response.get("error") {
            Some(Value::String(error)) => Err(CallError::Kernel(clean_error(error))),
            Some(other) if !other.is_null() => Err(CallError::Kernel(other.to_string())),
            _ => Ok(response.get("result").cloned().unwrap_or(Value::Null)),
        }
    }

    /// Run Lua in the kernel with `args` as `...`.
    pub fn eval(&mut self, code: &str, args: Vec<Value>) -> Result<Value, CallError> {
        let mut params = vec![json!(code)];
        params.extend(args);
        self.call("eval", Value::Array(params))
    }

    /// Stop a kernel this server started: ask it to quit, then insist.
    pub fn shutdown(&mut self) {
        if self.child.is_some() {
            self.runtime.clone().block_on(self.shutdown_async());
        }
    }

    async fn shutdown_async(&mut self) {
        let Some(mut child) = self.child.take() else {
            return;
        };
        if self.conn.is_some() {
            let _ = self.call_async("quit", json!([0])).await;
        }
        self.conn = None;
        if tokio::time::timeout(Duration::from_secs(5), child.wait()).await.is_err() {
            let _ = child.kill().await;
        }
        let _ = std::fs::remove_file(&self.socket);
    }
}

impl Drop for Kernel {
    fn drop(&mut self) {
        self.shutdown();
    }
}

/// The useful part of a Lua error: no traceback, no `runtime error:` prefix.
pub fn clean_error(error: &str) -> String {
    let text = error.split("\nstack traceback").next().unwrap_or(error);
    let text = text.trim();
    let text = text.strip_prefix("runtime error: ").unwrap_or(text);
    text.to_string()
}
