//! Helper processes and Unix sockets, for extensions that drive a program of
//! their own (a renderer, a language server) from Lua.
//!
//! Everything is addressed by number and moves as plain bytes, so `paw.api`
//! stays plain data. Reads never block. A process started with pipes is read
//! by a task on the kernel's I/O runtime (`crate::io_runtime`), which wakes
//! the kernel when bytes arrive, so that a script hears of them as an event
//! instead of polling; sockets are polled from a timer. Writes wait in
//! `poll(2)` for room, with a time limit. Handles live in the kernel, not in the Lua state, so they
//! survive `:reload`.

use std::collections::{BTreeMap, HashMap};
use std::fs::OpenOptions;
use std::io::{ErrorKind, Read, Write};
use std::os::fd::{AsFd, AsRawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use rustix::event::{PollFd, PollFlags, Timespec, poll};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::io::{AsyncRead, AsyncReadExt};
use tokio::task::AbortHandle;

/// How long a write may wait for the other side to make room.
const WRITE_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct SpawnOpts {
    pub env: BTreeMap<String, String>,
    pub cwd: Option<PathBuf>,
    /// File that receives the program's output and errors, appended to.
    /// Without it they are discarded. With `pipe` it receives the errors alone.
    pub log: Option<PathBuf>,
    /// Talk to the program over its standard input and output, as a
    /// language server is talked to.
    pub pipe: bool,
}

/// Called from the task reading a piped process's output when a piped process has written something.
pub type Wake = Arc<dyn Fn() + Send + Sync>;

/// What a piped process has written that has not been read yet.
#[derive(Default)]
struct Output {
    bytes: Vec<u8>,
    /// The process closed its output (it ended, most likely).
    closed: bool,
    /// `arrived` has named it already; reading it lets it be named again.
    told: bool,
}

/// The kernel's ends of a piped process's input and output.
struct Pipe {
    input: Option<ChildStdin>,
    output: Arc<Mutex<Output>>,
    /// The task reading `output`, stopped when the process is forgotten,
    /// even if something the process started still holds its output open.
    reading: AbortHandle,
}

impl Drop for Pipe {
    fn drop(&mut self) {
        self.reading.abort();
    }
}

#[derive(Default)]
pub struct Io {
    next: u64,
    procs: HashMap<u64, Child>,
    pipes: HashMap<u64, Pipe>,
    listeners: HashMap<u64, (UnixListener, PathBuf)>,
    streams: HashMap<u64, UnixStream>,
    wake: Option<Wake>,
}

impl Io {
    fn id(&mut self) -> u64 {
        self.next += 1;
        self.next
    }

    /// Have `wake` called whenever a piped process writes or ends.
    pub fn on_output(&mut self, wake: Wake) {
        self.wake = Some(wake);
    }

    pub fn spawn(&mut self, argv: &[String], opts: SpawnOpts) -> Result<u64> {
        let (program, args) = argv.split_first().context("nothing to run")?;
        let mut command = Command::new(program);
        command.args(args).envs(&opts.env);
        if let Some(cwd) = &opts.cwd {
            command.current_dir(cwd);
        }
        let log = match &opts.log {
            Some(path) => Some(
                OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(path)
                    .with_context(|| format!("opening {}", path.display()))?,
            ),
            None => None,
        };
        if opts.pipe {
            command.stdin(Stdio::piped()).stdout(Stdio::piped());
        } else {
            command.stdin(Stdio::null());
            match &log {
                Some(file) => command.stdout(file.try_clone()?),
                None => command.stdout(Stdio::null()),
            };
        }
        match log {
            Some(file) => command.stderr(file),
            None => command.stderr(Stdio::null()),
        };
        // A helper has no reason to outlive the program that drives it: if
        // the program ends without stopping it, however it ends, the helper
        // is asked to finish.
        #[cfg(target_os = "linux")]
        // SAFETY: the closure runs between fork and exec and calls only `prctl`, which is
        // async-signal-safe; it takes no lock and does not allocate.
        unsafe {
            command.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let mut child = command
            .spawn()
            .with_context(|| format!("starting {program}"))?;
        let id = self.id();
        if opts.pipe {
            let input = child.stdin.take().context("no pipe to the program")?;
            let from = child.stdout.take().context("no pipe from the program")?;
            // A write waits with a limit of its own rather than hold the
            // kernel up for as long as the program does not read.
            // SAFETY: `fd` is the open descriptor of `input`, which lives past the calls;
            // fcntl with F_GETFL and F_SETFL reads and sets flags only.
            unsafe {
                let fd = input.as_raw_fd();
                libc::fcntl(fd, libc::F_SETFL, libc::fcntl(fd, libc::F_GETFL) | libc::O_NONBLOCK);
            }
            let output = Arc::new(Mutex::new(Output::default()));
            let reading = crate::io_runtime::handle().and_then(|runtime| {
                let _inside = runtime.enter();
                let from = tokio::process::ChildStdout::from_std(from)?;
                let read = reader(from, output.clone(), self.wake.clone());
                Ok(runtime.spawn(read).abort_handle())
            });
            let reading = match reading {
                Ok(reading) => reading,
                Err(err) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(err).context("starting to read the program's output");
                }
            };
            self.pipes.insert(id, Pipe { input: Some(input), output, reading });
        }
        self.procs.insert(id, child);
        Ok(id)
    }

    /// The piped processes that have written something, or ended, since they
    /// were last read. Each is named once until it is read again.
    pub fn arrived(&mut self) -> Vec<u64> {
        let mut ids = Vec::new();
        for (id, pipe) in &self.pipes {
            let mut output = pipe.output.lock().unwrap();
            if !output.told && (output.closed || !output.bytes.is_empty()) {
                output.told = true;
                ids.push(*id);
            }
        }
        ids.sort_unstable();
        ids
    }

    /// Up to `max` bytes a piped process has written: empty when nothing is
    /// waiting, `None` once it has closed its output and all of it was read.
    pub fn read_output(&mut self, id: u64, max: usize) -> Result<Option<Vec<u8>>> {
        let pipe = self
            .pipes
            .get(&id)
            .with_context(|| format!("no process {id} with pipes"))?;
        let mut output = pipe.output.lock().unwrap();
        output.told = false;
        if output.bytes.is_empty() {
            return Ok((!output.closed).then(Vec::new));
        }
        let n = max.clamp(1, 1 << 24).min(output.bytes.len());
        Ok(Some(output.bytes.drain(..n).collect()))
    }

    /// Write all of `data` to a piped process's input, waiting for room if
    /// it is slow to read.
    pub fn write_input(&mut self, id: u64, data: &[u8]) -> Result<()> {
        let input = self
            .pipes
            .get_mut(&id)
            .with_context(|| format!("no process {id} with pipes"))?
            .input
            .as_mut()
            .with_context(|| format!("the input of process {id} is closed"))?;
        write_all(input, data, || format!("process {id}"))
    }

    /// Close a piped process's input, which tells most programs to finish.
    pub fn close_input(&mut self, id: u64) -> Result<()> {
        self.pipes
            .get_mut(&id)
            .with_context(|| format!("no process {id} with pipes"))?
            .input = None;
        Ok(())
    }

    /// `{ running, code, pid }`; `code` is nil while running or when a signal ended it.
    pub fn status(&mut self, id: u64) -> Result<Value> {
        let child = self
            .procs
            .get_mut(&id)
            .with_context(|| format!("no process {id}"))?;
        let pid = child.id();
        Ok(match child.try_wait()? {
            None => json!({ "running": true, "pid": pid }),
            Some(status) => json!({ "running": false, "code": status.code(), "pid": pid }),
        })
    }

    /// Ask a process to finish, as Ctrl-C in a terminal would, and leave it
    /// the time to: `status` says when it has, and `kill` forgets it.
    pub fn stop(&mut self, id: u64) -> Result<()> {
        let child = self
            .procs
            .get_mut(&id)
            .with_context(|| format!("no process {id}"))?;
        if child.try_wait()?.is_none() {
            // SAFETY: the child has not been reaped (`try_wait` found it running), so its pid
            // is still ours; kill reads no memory.
            unsafe {
                libc::kill(child.id() as libc::pid_t, libc::SIGTERM);
            }
        }
        Ok(())
    }

    /// Stop a process and forget it.
    pub fn kill(&mut self, id: u64) {
        self.pipes.remove(&id);
        if let Some(mut child) = self.procs.remove(&id) {
            let _ = child.kill();
            let _ = child.wait();
        }
    }

    /// Listen on a socket file, replacing a stale one.
    pub fn listen(&mut self, path: PathBuf) -> Result<u64> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
        }
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path)
            .with_context(|| format!("listening on {}", path.display()))?;
        listener.set_nonblocking(true)?;
        let id = self.id();
        self.listeners.insert(id, (listener, path));
        Ok(id)
    }

    pub fn connect(&mut self, path: PathBuf) -> Result<u64> {
        let stream = UnixStream::connect(&path)
            .with_context(|| format!("connecting to {}", path.display()))?;
        stream.set_nonblocking(true)?;
        let id = self.id();
        self.streams.insert(id, stream);
        Ok(id)
    }

    /// A connection waiting on a listener, if there is one.
    pub fn accept(&mut self, id: u64) -> Result<Option<u64>> {
        let (listener, _) = self
            .listeners
            .get(&id)
            .with_context(|| format!("no listener {id}"))?;
        match listener.accept() {
            Ok((stream, _)) => {
                stream.set_nonblocking(true)?;
                let id = self.id();
                self.streams.insert(id, stream);
                Ok(Some(id))
            }
            Err(err) if err.kind() == ErrorKind::WouldBlock => Ok(None),
            Err(err) => Err(err.into()),
        }
    }

    /// Up to `max` bytes that have arrived: empty when nothing has, `None`
    /// once the other side has closed the connection.
    pub fn read(&mut self, id: u64, max: usize) -> Result<Option<Vec<u8>>> {
        let stream = self
            .streams
            .get_mut(&id)
            .with_context(|| format!("no connection {id}"))?;
        let mut buf = vec![0u8; max.clamp(1, 1 << 24)];
        loop {
            return match stream.read(&mut buf) {
                Ok(0) => Ok(None),
                Ok(n) => {
                    buf.truncate(n);
                    Ok(Some(buf))
                }
                Err(err) if err.kind() == ErrorKind::WouldBlock => Ok(Some(Vec::new())),
                Err(err) if err.kind() == ErrorKind::Interrupted => continue,
                Err(err) if err.kind() == ErrorKind::ConnectionReset => Ok(None),
                Err(err) => Err(err.into()),
            };
        }
    }

    /// Write all of `data`, waiting for room if the other side is slow.
    pub fn write(&mut self, id: u64, data: &[u8]) -> Result<()> {
        let stream = self
            .streams
            .get_mut(&id)
            .with_context(|| format!("no connection {id}"))?;
        write_all(stream, data, || format!("connection {id}"))
    }

    /// Close a connection or a listener, removing a listener's socket file.
    pub fn close(&mut self, id: u64) {
        self.streams.remove(&id);
        if let Some((_, path)) = self.listeners.remove(&id) {
            let _ = std::fs::remove_file(path);
        }
    }
}

/// Write all of `data` to something that does not block, waiting for room
/// for at most `WRITE_TIMEOUT`.
fn write_all(to: &mut (impl Write + AsFd), data: &[u8], name: impl Fn() -> String) -> Result<()> {
    let deadline = Instant::now() + WRITE_TIMEOUT;
    let mut rest = data;
    while !rest.is_empty() {
        match to.write(rest) {
            Ok(0) => bail!("{} is closed", name()),
            Ok(n) => rest = &rest[n..],
            Err(err) if err.kind() == ErrorKind::WouldBlock => {
                let left = deadline.saturating_duration_since(Instant::now());
                if left.is_zero() {
                    bail!("{} stopped taking data", name());
                }
                wait_for_room(&*to, left)?;
            }
            Err(err) if err.kind() == ErrorKind::Interrupted => {}
            Err(err) if err.kind() == ErrorKind::BrokenPipe => bail!("{} is closed", name()),
            Err(err) => return Err(err.into()),
        }
    }
    Ok(())
}

/// Wait until `fd` takes data, is closed or fails, or `within` has passed;
/// the write that follows tells which.
fn wait_for_room(fd: impl AsFd, within: Duration) -> Result<()> {
    // `within` is at most WRITE_TIMEOUT, which a Timespec holds.
    let within = Timespec::try_from(within).context("a time limit too long to wait")?;
    let mut fds = [PollFd::new(&fd, PollFlags::OUT)];
    match poll(&mut fds, Some(&within)) {
        Ok(_) | Err(rustix::io::Errno::INTR) => Ok(()),
        Err(err) => Err(std::io::Error::from(err).into()),
    }
}

/// What the task reading a piped process's output does: keep what arrives
/// until it is read, and wake the kernel.
async fn reader(mut from: impl AsyncRead + Unpin, to: Arc<Mutex<Output>>, wake: Option<Wake>) {
    let mut buf = vec![0u8; 1 << 16];
    loop {
        let n = match from.read(&mut buf).await {
            Err(err) if err.kind() == ErrorKind::Interrupted => continue,
            Ok(n) => n,
            Err(_) => 0,
        };
        {
            let mut output = to.lock().unwrap();
            if n == 0 {
                output.closed = true;
            } else {
                output.bytes.extend_from_slice(&buf[..n]);
            }
        }
        if let Some(wake) = &wake {
            wake();
        }
        if n == 0 {
            return;
        }
    }
}

impl Drop for Io {
    fn drop(&mut self) {
        let ids: Vec<u64> = self.listeners.keys().copied().collect();
        for id in ids {
            self.close(id);
        }
        self.streams.clear();
        for pipe in self.pipes.values_mut() {
            pipe.input = None;
        }
        // A closed connection is how most helpers learn to quit, so give them a
        // moment to finish what they are writing before stopping them.
        let deadline = Instant::now() + Duration::from_millis(500);
        while Instant::now() < deadline
            && self
                .procs
                .values_mut()
                .any(|child| matches!(child.try_wait(), Ok(None)))
        {
            std::thread::sleep(Duration::from_millis(10));
        }
        let ids: Vec<u64> = self.procs.keys().copied().collect();
        for id in ids {
            self.kill(id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// An `Io` that counts how often it was woken.
    fn counted() -> (Io, Arc<AtomicUsize>) {
        let wakes = Arc::new(AtomicUsize::new(0));
        let mut io = Io::default();
        let count = wakes.clone();
        io.on_output(Arc::new(move || {
            count.fetch_add(1, Ordering::SeqCst);
        }));
        (io, wakes)
    }

    fn piped(io: &mut Io, script: &str) -> u64 {
        let argv = ["sh", "-c", script].map(String::from);
        io.spawn(&argv, SpawnOpts { pipe: true, ..Default::default() }).unwrap()
    }

    /// Everything a process writes until it closes its output, read as the
    /// kernel would: when it is named as having written.
    fn read_to_end(io: &mut Io, id: u64) -> Vec<u8> {
        let deadline = Instant::now() + Duration::from_secs(20);
        let mut all = Vec::new();
        loop {
            assert!(Instant::now() < deadline, "the process never closed its output");
            if !io.arrived().contains(&id) {
                std::thread::sleep(Duration::from_millis(2));
                continue;
            }
            loop {
                match io.read_output(id, 7).unwrap() {
                    None => return all,
                    Some(bytes) if bytes.is_empty() => break,
                    Some(bytes) => all.extend(bytes),
                }
            }
        }
    }

    #[test]
    fn a_piped_process_answers_what_it_is_sent_and_wakes_the_kernel() {
        let (mut io, wakes) = counted();
        let id = piped(&mut io, "cat");
        let line = b"{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}\n";
        io.write_input(id, line).unwrap();
        io.close_input(id).unwrap();
        assert_eq!(read_to_end(&mut io, id), line.to_vec());
        assert!(wakes.load(Ordering::SeqCst) >= 2, "woken for the bytes and for the end");
        assert!(io.write_input(id, b"more").is_err(), "nothing goes into a closed input");
        io.kill(id);
        assert!(io.read_output(id, 1).is_err(), "a killed process is forgotten");
    }

    #[test]
    fn a_write_waits_for_a_slow_reader_to_make_room() {
        let (mut io, _) = counted();
        let id = piped(&mut io, "sleep 0.3; wc -c");
        io.write_input(id, &vec![b'x'; 1 << 20]).unwrap();
        io.close_input(id).unwrap();
        let count = String::from_utf8(read_to_end(&mut io, id)).unwrap();
        assert_eq!(count.trim(), "1048576");
    }

    #[test]
    fn a_process_is_named_once_until_it_is_read() {
        let (mut io, _) = counted();
        let id = piped(&mut io, "printf one; read _; printf two");
        let deadline = Instant::now() + Duration::from_secs(20);
        while !io.arrived().contains(&id) {
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(2));
        }
        assert!(io.arrived().is_empty(), "not named again before it is read");
        assert_eq!(io.read_output(id, 100).unwrap(), Some(b"one".to_vec()));
        assert_eq!(io.read_output(id, 100).unwrap(), Some(Vec::new()), "nothing more yet");
        io.write_input(id, b"\n").unwrap();
        assert_eq!(read_to_end(&mut io, id), b"two".to_vec());
    }

    #[test]
    fn a_piped_process_writes_its_errors_to_the_log_and_not_the_pipe() {
        let (mut io, _) = counted();
        let dir = std::env::temp_dir().join(format!("paw-io-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let log = dir.join("helper.log");
        let argv = ["sh", "-c", "echo out; echo err >&2"].map(String::from);
        let opts = SpawnOpts { pipe: true, log: Some(log.clone()), ..Default::default() };
        let id = io.spawn(&argv, opts).unwrap();
        assert_eq!(read_to_end(&mut io, id), b"out\n".to_vec());
        let deadline = Instant::now() + Duration::from_secs(20);
        while io.status(id).unwrap()["running"] == true {
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(2));
        }
        assert_eq!(std::fs::read_to_string(&log).unwrap(), "err\n");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
