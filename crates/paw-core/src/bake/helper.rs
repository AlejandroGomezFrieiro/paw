//! The helper lane: a bake made by another program (ffmpeg, an
//! extension's helper), run and read on the kernel's I/O runtime.
//!
//! The helper writes its files into the entry's folder, which its command
//! line names as `{out}`; the entry goes in place whole when the helper
//! ends well. A cancelled helper gets SIGTERM, then SIGKILL a second later.
//! A failed one is told with the last lines it wrote on its errors.

use std::collections::VecDeque;
use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use tokio::io::{AsyncBufReadExt, AsyncRead, BufReader};
use tokio::process::Command;

use super::key::{BakeJob, EntryKey};
use super::scheduler::{Bake, Lane, Made, Task};
use super::store::{EntryWriter, Store, Write};

/// The lines of a helper's errors kept for its failure message.
const TAIL: usize = 4;

/// How a helper says how far it is: a line `<prefix><number>`, where the
/// number is `whole` when it is done ("out_time_us=" and the length in
/// microseconds, for ffmpeg's `-progress pipe:1`).
#[derive(Clone, Debug)]
pub struct ProgressLine {
    pub prefix: String,
    pub whole: f64,
}

impl ProgressLine {
    fn read(&self, line: &str) -> Option<f64> {
        let value: f64 = line.strip_prefix(&self.prefix)?.trim().parse().ok()?;
        Some(value / self.whole.max(1e-9))
    }
}

/// A bake made by a helper program.
pub struct Helper {
    /// For messages: "making a proxy of film.mkv".
    pub what: String,
    /// The program and its arguments; `{out}` is the entry's folder.
    pub argv: Vec<String>,
    pub progress: Option<ProgressLine>,
    pub store: Store,
    pub job: BakeJob,
    /// The helper's name and version: part of the entry's key.
    pub tool: String,
}

impl Bake for Helper {
    fn lane(&self) -> Lane {
        Lane::Helper
    }

    fn what(&self) -> String {
        self.what.clone()
    }

    fn start(self: Arc<Self>, task: Task) -> Result<()> {
        let key = EntryKey::new(&self.job, &self.tool);
        task.entry(key.id());
        let writer = match self.store.writer(&self.job, &key)? {
            Write::Make(writer) => writer,
            Write::Done(entry) => {
                task.end(Ok(Made::Entry(entry)));
                return Ok(());
            }
            Write::Busy => bail!("another paw on this machine makes it now"),
        };
        let command = self.command(&writer)?;
        crate::io_runtime::handle()?.spawn(async move {
            let result = run(command, &self, &task).await;
            let result = result.and_then(|()| Ok(Made::Entry(writer.commit()?)));
            task.end(result);
        });
        Ok(())
    }
}

impl Helper {
    fn command(&self, writer: &EntryWriter) -> Result<Command> {
        let (program, args) = self.argv.split_first().context("a helper with no program")?;
        let out = writer.file("");
        let out = out.to_string_lossy();
        let mut command = Command::new(program);
        command
            .args(args.iter().map(|a| a.replace("{out}", &out)))
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        #[cfg(target_os = "linux")]
        // SAFETY: the closure runs between fork and exec and makes only
        // system calls (`prctl`, `setpriority`, through rustix), which are
        // async-signal-safe; it takes no lock and does not allocate.
        unsafe {
            command.pre_exec(|| {
                // Not to outlive paw, and to give way to it.
                let _ = rustix::process::set_parent_process_death_signal(Some(rustix::process::Signal::TERM));
                super::native::lower_priority();
                Ok(())
            });
        }
        Ok(command)
    }
}

/// Run the helper to its end, or until the bake is cancelled.
async fn run(mut command: Command, helper: &Helper, task: &Task) -> Result<()> {
    let program = &helper.argv[0];
    let mut child = command.spawn().with_context(|| format!("starting {program}"))?;
    let pid = child.id().unwrap_or(0);
    task.pid(pid);
    let stdout = child.stdout.take().context("the helper's output")?;
    let stderr = child.stderr.take().context("the helper's errors")?;
    let progress = helper.progress.as_ref();
    let reading = async {
        tokio::join!(lines(stdout, task, progress), lines(stderr, task, progress)).1
    };
    let tail = tokio::select! {
        tail = reading => tail,
        () = task.until_cancelled() => {
            stop(&mut child, pid).await;
            bail!("cancelled");
        }
    };
    let status = child.wait().await?;
    if !status.success() {
        let why = tail.into_iter().collect::<Vec<_>>().join("\n");
        let why = if why.is_empty() { "it gave no reason".to_string() } else { why };
        return Err(anyhow!("{program} failed ({status}): {why}"));
    }
    Ok(())
}

/// The lines of one of the helper's streams, read for progress; the last
/// few, kept for a failure message.
async fn lines(stream: impl AsyncRead + Unpin, task: &Task, progress: Option<&ProgressLine>) -> VecDeque<String> {
    let mut tail = VecDeque::with_capacity(TAIL);
    let mut lines = BufReader::new(stream).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        if let Some(done) = progress.and_then(|p| p.read(&line)) {
            task.progress(done);
            continue;
        }
        if line.trim().is_empty() {
            continue;
        }
        if tail.len() == TAIL {
            tail.pop_front();
        }
        tail.push_back(line);
    }
    tail
}

/// SIGTERM, a second to end, then SIGKILL; reaped either way.
async fn stop(child: &mut tokio::process::Child, pid: u32) {
    // The helper's own process, not reaped yet: its id names no other.
    if let Some(pid) = i32::try_from(pid).ok().and_then(rustix::process::Pid::from_raw) {
        let _ = rustix::process::kill_process(pid, rustix::process::Signal::TERM);
    }
    if tokio::time::timeout(Duration::from_secs(1), child.wait()).await.is_err() {
        let _ = child.kill().await;
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::time::Instant;

    use super::*;
    use crate::bake::key::{Output, Stream};
    use crate::bake::scheduler::{Priority, Scheduler, Status};

    fn helper(store: &Store, script: &str) -> Arc<dyn Bake> {
        Arc::new(Helper {
            what: "a test helper".into(),
            argv: vec!["sh".into(), "-c".into(), script.into()],
            progress: Some(ProgressLine { prefix: "done=".into(), whole: 100.0 }),
            store: store.clone(),
            job: BakeJob {
                op: "test".into(),
                version: 1,
                params: serde_json::json!({ "script": script }),
                inputs: vec![],
                output: Output { stream: Stream::Data, rate: None, format: None },
            },
            tool: "sh".into(),
        })
    }

    /// Poll until `until` holds, for at most 10 s.
    fn poll_until(bakes: &mut Scheduler<u32>, wants: &HashMap<u32, Priority>, until: impl Fn(&Scheduler<u32>) -> bool) {
        let deadline = Instant::now() + Duration::from_secs(10);
        while !until(bakes) {
            assert!(Instant::now() < deadline, "timed out");
            bakes.poll(wants, Duration::ZERO);
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    #[test]
    fn a_cancelled_helper_is_killed() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::new(dir.path().join("bakes"), u64::MAX);
        let mut bakes: Scheduler<u32> = Scheduler::new(1, 1);
        // It ignores SIGTERM: only the kill ends it.
        bakes.ask(&1, || Some(helper(&store, "trap '' TERM; echo $$ > {out}/pid; echo done=50; sleep 30")));
        let wants = HashMap::from([(1, Priority::Playing)]);
        poll_until(&mut bakes, &wants, |b| b.progress(&1) > 0.4);
        let pid_file = std::fs::read_dir(dir.path().join("bakes/tmp"))
            .unwrap()
            .flatten()
            .map(|e| e.path().join("pid"))
            .find(|p| p.is_file())
            .unwrap();
        let pid = std::fs::read_to_string(pid_file).unwrap().trim().to_string();
        assert!(std::path::Path::new(&format!("/proc/{pid}")).exists());
        poll_until(&mut bakes, &HashMap::new(), |b| b.status(&1) == Status::Unknown);
        assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists(), "the helper is gone");
        assert!(bakes.failures.is_empty(), "a cancel is not a failure: {:?}", bakes.failures);
        // A helper that fails is told with what it said.
        bakes.ask(&2, || Some(helper(&store, "echo no room >&2; exit 3")));
        let wants = HashMap::from([(2, Priority::Background)]);
        poll_until(&mut bakes, &wants, |b| b.status(&2) == Status::Failed);
        assert!(bakes.failures[0].contains("no room"), "{:?}", bakes.failures);
    }
}
