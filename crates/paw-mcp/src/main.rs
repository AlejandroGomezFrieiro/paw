//! `paw-mcp`: a Model Context Protocol server for paw.
//!
//! It speaks MCP on stdin and stdout through `rmcp`, the official Rust SDK,
//! and drives a paw kernel through the kernel's control socket. Everything it
//! does to the project goes through `paw.api`, so it is undoable like any
//! other edit. Logs go to stderr; stdout carries protocol messages only.

mod audio;
mod check;
mod format;
mod kernel;
mod music;
mod reference;
mod resources;
mod schema;
mod server;
mod tools;

use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use clap::Parser;

use kernel::{Kernel, SpawnOpts};
use tools::{Policy, Tools};

/// paw-mcp: a Model Context Protocol server for paw, on stdin and stdout
#[derive(Parser, Debug)]
#[command(
    name = "paw-mcp",
    version,
    override_usage = "paw-mcp [options]                     attach to a running kernel\n       \
                      paw-mcp --spawn [project] [-- kernel options...]\n                                             \
                      start a headless kernel of its own"
)]
struct Cli {
    /// The kernel's control socket (default: $PAW_SOCKET, else
    /// $XDG_RUNTIME_DIR/paw.sock, where `paw` listens)
    #[arg(long, value_name = "path")]
    socket: Option<PathBuf>,
    /// Start `paw --headless` and stop it on exit; anything after `--` is
    /// passed to it (such as --audio null)
    #[arg(long)]
    spawn: bool,
    /// The `paw` binary for --spawn (default: $PAW_BIN, the one beside this
    /// program, or `paw` on the path)
    #[arg(long, value_name = "path")]
    paw: Option<PathBuf>,
    /// Where relative paths start and files may be written (default: the
    /// current directory)
    #[arg(long, value_name = "dir")]
    root: Option<PathBuf>,
    /// Offer the escape hatches: lua, run_command and send_keys, which run
    /// arbitrary code in paw
    #[arg(long)]
    allow_eval: bool,
    /// Let save and render write outside --root
    #[arg(long)]
    allow_any_path: bool,
    /// How long to wait for the kernel per call
    #[arg(long, value_name = "secs", default_value_t = 600)]
    timeout: u64,
    /// The project to open, with --spawn
    #[arg(value_name = "project")]
    project: Option<PathBuf>,
    /// Options for the kernel, with --spawn
    #[arg(last = true, value_name = "kernel options")]
    kernel_args: Vec<String>,
}

/// The command line, or `None` when it asked for the help or the version,
/// which go to stderr: stdout is the protocol's.
fn parse_args() -> Result<Option<Cli>> {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(err) if !err.use_stderr() => {
            eprint!("{}", err.render());
            return Ok(None);
        }
        Err(err) => err.exit(),
    };
    if !cli.spawn && (cli.project.is_some() || !cli.kernel_args.is_empty()) {
        bail!("a project file and kernel options only go with --spawn");
    }
    if cli.spawn && cli.socket.is_some() {
        bail!("--spawn starts its own kernel; --socket attaches to one: pick one");
    }
    Ok(Some(cli))
}

fn policy(cli: &Cli) -> Result<Policy> {
    let root = match &cli.root {
        Some(root) => std::path::absolute(root)?
            .canonicalize()
            .with_context(|| format!("--root {}", root.display()))?,
        None => std::env::current_dir().context("no working directory")?,
    };
    Ok(Policy {
        allow_eval: cli.allow_eval,
        allow_any_path: cli.allow_any_path,
        root,
    })
}

fn run() -> Result<()> {
    let Some(cli) = parse_args()? else {
        return Ok(());
    };
    let policy = policy(&cli)?;
    // One worker thread is plenty: the protocol and the kernel's socket. The
    // tools run on the runtime's blocking threads.
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .enable_all()
        .build()
        .context("starting the runtime")?;
    let timeout = Duration::from_secs(cli.timeout.max(1));
    let mut kernel = if cli.spawn {
        let project = match &cli.project {
            Some(p) => Some(std::path::absolute(p)?),
            None => None,
        };
        let opts = SpawnOpts {
            binary: cli.paw.clone().unwrap_or_else(kernel::default_binary),
            project,
            args: cli.kernel_args,
        };
        Kernel::spawned(opts, timeout, runtime.handle().clone())
    } else {
        let socket = cli.socket.unwrap_or_else(kernel::default_socket);
        Kernel::attach(socket, timeout, runtime.handle().clone())
    };
    if kernel.is_spawned() {
        // Start now, so the first tool call is quick and a broken setup shows
        // in the log at once; a failure is reported again on each call.
        if let Err(err) = kernel.start() {
            eprintln!("paw-mcp: {err}");
        }
    }
    eprintln!(
        "paw-mcp: kernel socket {}; root {}; eval {}; writes {}",
        kernel.socket.display(),
        policy.root.display(),
        if policy.allow_eval { "allowed" } else { "off" },
        if policy.allow_any_path { "anywhere" } else { "under the root only" }
    );
    let server = server::PawServer::new(Tools { kernel, policy });
    let tools = server.tools();
    runtime.block_on(server.serve_stdio())?;
    let mut tools = tools.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
    eprintln!(
        "paw-mcp: stdin closed{}",
        if tools.kernel.is_spawned() { "; stopping the kernel" } else { "" }
    );
    tools.kernel.shutdown();
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("paw-mcp: {err:#}");
            ExitCode::FAILURE
        }
    }
}
