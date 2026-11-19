//! The `paw` command: start the kernel with a terminal UI, without one, to run
//! a script, or to talk to an instance that is already running.

mod graphics;
mod terminal;

use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use paw_core::{Kernel, KernelOpts, rpc};
use paw_engine::Registry;
use paw_engine::backend::BackendOptions;
use serde_json::Value;

const HELP: &str = "\
paw: a personal audio workstation

Usage:
  paw [options] [project]         open the terminal UI (a sound file starts a project with it)
  paw -l <script.lua> [args...]   run a Lua script without a UI, then exit
  paw --headless [project]        run without a UI until told to quit
  paw ctl [--json] <method> [params...]
                                  call a running instance over its socket
  paw attach                      show a running instance's terminal UI here
  paw doctor [options]            check the audio, MIDI, plugins and environment, and print a report
  paw clip cat <file.midi2>       print a MIDI 2.0 clip file as text, one note to a line
                                  (git's textconv for project folders)

Options:
  -e <lua>          run Lua code after startup (repeatable)
  --keys <keys>     type keys after startup, such as 'jj<Space>'
  --clean           skip your configuration and extensions
  --config <dir>    configuration directory (default: ~/.config/paw)
  --runtime <dir>   load the Lua runtime from disk instead of the built-in copy
  --audio <name>    audio backend: auto, null, pipewire, alsa, jack
  --rate <hz>       sample rate
  --buffer <n>      frames per audio callback
  --output <name>   output device by name or part of it (see :audio)
  --input <name>    input device by name or part of it
  --no-input        do not open the audio device's input
  --listen <path>   control socket path (default: $XDG_RUNTIME_DIR/paw.sock)
  --no-listen       do not open a control socket
  --listen-tcp <address>
                    also take connections from the network, on host:port
                    (127.0.0.1:7700; 0.0.0.0:7700 for any machine that knows
                    the token), in TLS with a certificate made the first time
  --no-tls          take them in the clear instead: for a network you trust
  --token-file <path>
                    where the token for network connections is kept
                    (default: ~/.local/state/paw/token, made if missing)
  --no-plugins      do not look for CLAP, LV2 and VST3 plugins
  --plugins-in-process
                    load plugins into this process, not each into its own
  --plugins-offline open the project with every plugin offline (:plugins.online)
  -h, --help        show this help
  -V, --version     show the version

ctl and attach reach the instance on this machine's socket, or:
  --socket <path>           another socket
  --connect <host:port>     an instance listening on the network, with
  --token <token> or --token-file <path> (or $PAW_TOKEN)
  --accept-certificate      take the certificate it shows though another was
                            remembered for it (after it made a new one)
  --no-tls                  connect in the clear, to one started with --no-tls
attach also takes --listen-audio, to play the instance's sound on this machine
  (about 1 Mbit/s), or --listen-audio-to <file.wav> to write it to a file
doctor options: --seconds <n> (length of the dropout runs), --plugin <name> (repeatable),
  --only <ids> (comma separated), and the audio options above (--audio, --output, ...)

ctl examples:
  paw ctl eval 'return paw.transport.position'
  paw ctl cmd transport.toggle
  paw ctl --json eval 'return paw.project.tempo'
  paw ctl track_add '{\"name\": \"Bass\"}'
  paw ctl --connect studio:7700 --token-file studio.token cmd transport.toggle

In an attached terminal, `:detach` leaves and the instance runs on, and
`:upload <file>` brings a sound file from this machine into the project.
";

#[derive(Default)]
struct Args {
    project: Option<PathBuf>,
    script: Option<PathBuf>,
    script_args: Vec<String>,
    exprs: Vec<String>,
    keys: Vec<String>,
    headless: bool,
    clean: bool,
    config: Option<PathBuf>,
    runtime: Option<PathBuf>,
    audio: Option<String>,
    rate: Option<u32>,
    buffer: Option<u32>,
    output: Option<String>,
    input: Option<String>,
    no_input: bool,
    listen: Option<PathBuf>,
    no_listen: bool,
    listen_tcp: Option<String>,
    no_tls: bool,
    token_file: Option<PathBuf>,
    no_plugins: bool,
    plugins_in_process: bool,
    plugins_offline: bool,
    /// Run as `paw doctor`: a script, but with the sound device unless told otherwise.
    doctor: bool,
}

fn parse_args(mut argv: impl Iterator<Item = String>) -> Result<Option<Args>> {
    let mut args = Args::default();
    while let Some(arg) = argv.next() {
        let mut value = |name: &str| argv.next().with_context(|| format!("{name} needs a value"));
        match arg.as_str() {
            "-h" | "--help" => {
                print!("{HELP}");
                return Ok(None);
            }
            "-V" | "--version" => {
                println!("paw {}", env!("CARGO_PKG_VERSION"));
                return Ok(None);
            }
            "-l" => {
                args.script = Some(value("-l")?.into());
                args.script_args = argv.by_ref().collect();
            }
            "-e" => args.exprs.push(value("-e")?),
            "--keys" => args.keys.push(value("--keys")?),
            "--headless" => args.headless = true,
            "--clean" => args.clean = true,
            "--config" => args.config = Some(value("--config")?.into()),
            "--runtime" => args.runtime = Some(value("--runtime")?.into()),
            "--audio" => args.audio = Some(value("--audio")?),
            "--rate" => {
                args.rate = Some(value("--rate")?.parse().context("--rate takes a number")?)
            }
            "--buffer" => {
                args.buffer = Some(
                    value("--buffer")?
                        .parse()
                        .context("--buffer takes a number")?,
                )
            }
            "--output" => args.output = Some(value("--output")?),
            "--input" => args.input = Some(value("--input")?),
            "--no-input" => args.no_input = true,
            "--listen" => args.listen = Some(value("--listen")?.into()),
            "--no-listen" => args.no_listen = true,
            "--listen-tcp" => args.listen_tcp = Some(value("--listen-tcp")?),
            "--token-file" => args.token_file = Some(value("--token-file")?.into()),
            "--no-tls" => args.no_tls = true,
            "--no-plugins" => args.no_plugins = true,
            "--plugins-in-process" => args.plugins_in_process = true,
            "--plugins-offline" => args.plugins_offline = true,
            other if other.starts_with('-') => bail!("unknown option `{other}` (see --help)"),
            _ if args.project.is_none() => args.project = Some(arg.into()),
            _ => bail!("unexpected argument `{arg}`"),
        }
    }
    // paw-gui starts the kernel with `--listen`: a kernel that would not
    // listen must stop at once rather than leave it waiting for the socket.
    if args.no_listen && args.listen.is_some() {
        bail!("--no-listen and --listen contradict each other (the window always talks to the kernel through a socket)");
    }
    Ok(Some(args))
}

fn config_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("paw")
}

/// The terminal's stderr, kept while fd 2 points at a log file.
static REAL_STDERR: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(-1);

/// Send everything written to stderr into a file instead of the terminal.
fn quiet_stderr(log: &std::path::Path) {
    use std::os::fd::AsRawFd;
    if let Some(dir) = log.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let Ok(file) = std::fs::File::create(log) else {
        return;
    };
    unsafe {
        REAL_STDERR.store(libc::dup(2), std::sync::atomic::Ordering::Relaxed);
        libc::dup2(file.as_raw_fd(), 2);
    }
}

/// Undo [`quiet_stderr`], so that a final error message reaches the terminal.
fn restore_stderr() {
    let saved = REAL_STDERR.swap(-1, std::sync::atomic::Ordering::Relaxed);
    if saved >= 0 {
        unsafe {
            libc::dup2(saved, 2);
            libc::close(saved);
        }
    }
}

fn cache_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
        .unwrap_or_else(std::env::temp_dir);
    base.join("paw")
}

/// Connect to the instance `ctl` and `attach` are pointed at by the options
/// at the front of their arguments, which are taken off.
fn connect(argv: &mut std::iter::Peekable<impl Iterator<Item = String>>) -> Result<rpc::Connection> {
    let mut socket = rpc::default_path();
    let mut address = None;
    let mut token = std::env::var("PAW_TOKEN").ok();
    let mut wire = rpc::Wire::default();
    let mut accept_new = false;
    while let Some(option) = argv.peek().filter(|a| a.starts_with("--")).cloned() {
        argv.next();
        let mut value = || argv.next().with_context(|| format!("{option} needs a value"));
        match option.as_str() {
            "--socket" => socket = value()?.into(),
            "--connect" => address = Some(value()?),
            "--token" => token = Some(value()?),
            "--no-tls" => wire = rpc::Wire::Plain,
            "--accept-certificate" => accept_new = true,
            "--token-file" => {
                let path = value()?;
                let text = std::fs::read_to_string(&path)
                    .with_context(|| format!("reading the token in {path}"))?;
                token = Some(text.trim().to_string());
            }
            other => bail!("unknown option `{other}` (see --help)"),
        }
    }
    match address {
        Some(address) => {
            // On the machine the instance runs on, its token is at hand.
            let token = match token {
                Some(token) => token,
                None => std::fs::read_to_string(rpc::token_path())
                    .map(|text| text.trim().to_string())
                    .context("--connect needs the token: --token, --token-file or $PAW_TOKEN")?,
            };
            if let rpc::Wire::Tls { accept_new: accept, .. } = &mut wire {
                *accept = accept_new;
            }
            let connection = rpc::Connection::tcp_with(&address, &token, &wire)?;
            if let Some(print) = &connection.trusted_now {
                eprintln!(
                    "paw: {address} is trusted from now on: its certificate is {print} \
                     (remembered in {})",
                    rpc::known_path().display()
                );
            }
            Ok(connection)
        }
        None => rpc::Connection::unix(&socket),
    }
}

/// `paw ctl [--json] <method> [params...]`: each parameter is JSON, or a plain
/// string when it does not parse as JSON. With `--json` the answer is one line
/// of JSON on stdout, `{"ok": true, "result": ...}` or `{"ok": false,
/// "error": "..."}` (and the exit status 1), whatever went wrong.
fn ctl(argv: impl Iterator<Item = String>) -> Result<()> {
    let mut argv: Vec<String> = argv.collect();
    // The option may stand among the connection's: take it out, leaving the
    // values of the options that take one alone.
    let mut json = false;
    let mut i = 0;
    while i < argv.len() && argv[i].starts_with("--") {
        match argv[i].as_str() {
            "--json" => {
                json = true;
                argv.remove(i);
            }
            "--socket" | "--connect" | "--token" | "--token-file" => i += 2,
            _ => i += 1,
        }
    }
    let outcome = ctl_call(argv.into_iter());
    if !json {
        match outcome? {
            Value::Null => {}
            Value::String(text) => println!("{text}"),
            other => println!("{}", serde_json::to_string_pretty(&other)?),
        }
        return Ok(());
    }
    match outcome {
        Ok(result) => println!("{}", serde_json::json!({ "ok": true, "result": result })),
        Err(err) => {
            println!("{}", serde_json::json!({ "ok": false, "error": format!("{err:#}") }));
            std::process::exit(1);
        }
    }
    Ok(())
}

fn ctl_call(argv: impl Iterator<Item = String>) -> Result<Value> {
    let mut argv = argv.peekable();
    let mut connection = connect(&mut argv)?;
    let method = argv.next().context(
        "usage: paw ctl [--json] [--socket <path> | --connect <host:port>] <method> [params...]",
    )?;
    let params: Vec<Value> = argv
        .map(|p| serde_json::from_str(&p).unwrap_or(Value::String(p)))
        .collect();
    connection.call(&method, Value::Array(params))
}

/// Where an attached terminal plays the instance's sound.
#[derive(Clone)]
enum Hear {
    Device,
    File(PathBuf),
}

/// Start hearing the instance here, or stop. What went wrong is said on
/// the instance's screen.
fn listen(connection: &mut rpc::Connection, player: &mut Option<paw_listen::Player>, hear: Option<&Hear>) {
    let started = match hear {
        None => {
            *player = None;
            connection.notify("monitor.unlisten", serde_json::json!([])).map(|_| ())
        }
        Some(hear) => (|| {
            let opened = match hear {
                Hear::Device => paw_listen::Player::device()?,
                Hear::File(path) => paw_listen::Player::file(path, 48000)?,
            };
            connection.call("monitor.listen", serde_json::json!([]))?;
            *player = Some(opened);
            Ok(())
        })(),
    };
    if let Err(err) = started {
        let message = format!("cannot play the instance's sound here: {err:#}");
        let _ = connection.notify("eval", serde_json::json!(["paw.notify(..., 'error')", message]));
    }
}

/// `paw attach`: this terminal becomes a terminal of a running instance,
/// which may be on another machine, with a seat of its own there: its own
/// cursor, mode and selection in the one project. `:detach` leaves, and so
/// does the instance ending. With `--listen-audio` it plays what the
/// instance plays (`--listen-audio-to <file.wav>` writes it to a file).
fn attach(argv: impl Iterator<Item = String>) -> Result<()> {
    // The options of attach's own; the rest say where the instance is.
    let mut rest = Vec::new();
    let mut hear = None;
    let mut argv = argv.into_iter();
    while let Some(arg) = argv.next() {
        match arg.as_str() {
            "--listen-audio" => hear = Some(Hear::Device),
            "--listen-audio-to" => {
                hear = Some(Hear::File(argv.next().context("--listen-audio-to needs a file")?.into()))
            }
            _ => rest.push(arg),
        }
    }
    let mut argv = rest.into_iter().peekable();
    let mut connection = connect(&mut argv)?;
    if let Some(extra) = argv.next() {
        bail!("unexpected argument `{extra}`");
    }
    let (input, typed) = std::sync::mpsc::channel();
    let (mut screen, width, height) = terminal::Terminal::start(move |event| input.send(event).is_ok())?;
    connection.call("ui.attach", serde_json::json!([width, height, screen.caps().to_json()]))?;
    let mut player = None;
    if hear.is_some() {
        listen(&mut connection, &mut player, hear.as_ref());
    }
    let mut grid = paw_core::grid::Grid::new(width, height);
    use paw_core::Frontend;
    loop {
        // What was typed goes out; what the instance shows comes in.
        let mut idle = true;
        while let Ok(event) = typed.try_recv() {
            idle = false;
            connection.notify("ui.input", serde_json::json!([paw_core::remote::input_json(&event)]))?;
        }
        loop {
            match connection.events.try_recv() {
                Ok((name, payload)) => {
                    idle = false;
                    match name.as_str() {
                        "ui.grid" => {
                            let cursor = paw_core::remote::apply(&mut grid, &payload)?;
                            screen.present(&grid, cursor)?;
                        }
                        "ui.detached" => return Ok(()),
                        // `:upload`: a file on this machine, for the instance.
                        "file.wanted" => send_wanted(&mut connection, &payload),
                        "audio.frame" => {
                            if let Some(player) = &player {
                                let _ = player.push(&payload);
                            }
                        }
                        // `:listen`: start or stop hearing the instance here.
                        "monitor.toggle" => {
                            let wanted = player.is_none().then(|| hear.clone().unwrap_or(Hear::Device));
                            listen(&mut connection, &mut player, wanted.as_ref());
                        }
                        _ => {}
                    }
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => break,
                // The instance ended, or the connection did.
                Err(std::sync::mpsc::TryRecvError::Disconnected) => return Ok(()),
            }
        }
        if idle {
            std::thread::sleep(std::time::Duration::from_millis(4));
        }
    }
}

/// Send the file a `file.wanted` event names, from this machine, and import
/// it; what went wrong is said on the instance's screen.
fn send_wanted(connection: &mut rpc::Connection, payload: &Value) {
    let Some(asked) = payload["path"].as_str() else { return };
    let path = match (asked.strip_prefix("~/"), std::env::var_os("HOME")) {
        (Some(rest), Some(home)) => PathBuf::from(home).join(rest),
        _ => PathBuf::from(asked),
    };
    let sent = if payload["import"].as_bool().unwrap_or(false) {
        connection.send_and_import(&path)
    } else {
        connection.send_file(&path)
    };
    if let Err(err) = sent {
        let message = format!("could not send {asked}: {err:#}");
        let _ = connection.notify("eval", serde_json::json!(["paw.notify(..., 'error')", message]));
    }
}

/// Where `extensions/doctor/shell.lua` is: under `$PAW_HOME`, or beside the
/// binary in a source tree (the binary is in `target/release`), or here.
fn doctor_script() -> Result<PathBuf> {
    let mut roots: Vec<PathBuf> = std::env::var_os("PAW_HOME").map(PathBuf::from).into_iter().collect();
    if let Ok(exe) = std::env::current_exe() {
        roots.extend(exe.ancestors().skip(1).take(4).map(PathBuf::from));
    }
    roots.extend(std::env::current_dir());
    roots
        .iter()
        .map(|root| root.join("extensions/doctor/shell.lua"))
        .find(|path| path.is_file())
        .context("cannot find extensions/doctor/shell.lua: set PAW_HOME to the source tree")
}

/// `paw doctor [options]`: the options the doctor itself takes become the
/// script's arguments (`--seconds=20`); the rest are the program's own.
fn doctor_args(argv: impl Iterator<Item = String>) -> Result<Option<Args>> {
    let mut own = Vec::new();
    let mut rest = Vec::new();
    let mut argv = argv.peekable();
    while let Some(arg) = argv.next() {
        match arg.as_str() {
            "--seconds" | "--plugin" | "--only" => {
                let value = argv.next().with_context(|| format!("{arg} needs a value"))?;
                own.push(format!("{arg}={value}"));
            }
            _ => rest.push(arg),
        }
    }
    let Some(mut args) = parse_args(rest.into_iter())? else {
        return Ok(None);
    };
    args.script = Some(doctor_script()?);
    args.script_args = own;
    args.doctor = true;
    Ok(Some(args))
}

/// The file a project path names: a folder's `project.toml`, or itself.
fn project_file_of(path: &std::path::Path) -> Option<PathBuf> {
    let path = if path.is_dir() {
        path.join("project.toml")
    } else {
        path.to_path_buf()
    };
    path.canonicalize().ok()
}

/// Whether the paw on this machine's socket has this project open.
fn running_has(project: &std::path::Path) -> bool {
    let Some(wanted) = project_file_of(project) else {
        return false;
    };
    let socket = rpc::default_path();
    if !socket.exists() {
        return false;
    }
    let Ok(mut connection) = rpc::Connection::unix(&socket) else {
        return false;
    };
    let Ok(Value::String(open)) =
        connection.call("eval", serde_json::json!(["return paw.api.project_get().path"]))
    else {
        return false;
    };
    project_file_of(std::path::Path::new(&open)).is_some_and(|open| open == wanted)
}

/// `paw clip cat <file.midi2>`: a MIDI 2.0 clip file as text, one note or
/// controller move to a line, for `git diff` (as its textconv) and reading.
fn clip_command(mut argv: impl Iterator<Item = String>) -> Result<i32> {
    match (argv.next().as_deref(), argv.next()) {
        (Some("cat"), Some(file)) => {
            let bytes = std::fs::read(&file).with_context(|| format!("reading {file}"))?;
            let clip = paw_core::clipfile::decode(&bytes).with_context(|| file.clone())?;
            print!("{}", paw_core::clipfile::text(&clip));
            Ok(0)
        }
        _ => bail!("usage: paw clip cat <file.midi2>"),
    }
}

fn run() -> Result<i32> {
    let mut argv = std::env::args().skip(1).peekable();
    let doctor = argv.peek().map(String::as_str) == Some("doctor");
    if doctor {
        argv.next();
    }
    if argv.peek().map(String::as_str) == Some("clip") {
        argv.next();
        return clip_command(argv);
    }
    if argv.peek().map(String::as_str) == Some("ctl") {
        argv.next();
        ctl(argv)?;
        return Ok(0);
    }
    if argv.peek().map(String::as_str) == Some("attach") {
        argv.next();
        let result = attach(argv);
        terminal::restore();
        result?;
        return Ok(0);
    }
    // Started by a running instance to hold one plugin, or to look into
    // one plugin file, in a process of its own.
    match argv.peek().map(String::as_str) {
        Some("plugin-host") => {
            let args: Vec<String> = argv.skip(1).collect();
            // A device written in Lua is held the way a plugin is.
            if args.first().is_some_and(|kind| kind.starts_with("lua:")) {
                return Ok(paw_plugins::sandbox::serve_with(&args, |_, rate, block| {
                    paw_luadev::serve_make(rate, block)
                }));
            }
            return Ok(paw_plugins::sandbox::serve(&args));
        }
        Some("plugin-scan") => {
            let args: Vec<String> = argv.skip(1).collect();
            if args.first().map(String::as_str) == Some("lua") {
                return Ok(paw_luadev::scan_main(&args[1..]));
            }
            return Ok(paw_plugins::scan_main(&args));
        }
        _ => {}
    }
    let parsed = if doctor { doctor_args(argv)? } else { parse_args(argv)? };
    let Some(args) = parsed else {
        return Ok(0);
    };
    let scripted = args.script.is_some();
    // A project that a running paw has open: this terminal joins it as a
    // new seat, so that two people edit the one project, not two copies.
    if !scripted
        && !args.headless
        && args.listen.is_none()
        && let Some(project) = &args.project
        && running_has(project)
    {
        eprintln!(
            "paw: {} is open in a running paw: joining it as a new seat (`:detach` leaves)",
            project.display()
        );
        let result = attach(std::iter::empty());
        terminal::restore();
        result?;
        return Ok(0);
    }
    // A terminal older than the display it names cannot open a plugin's
    // window. Put that right while this is still the only thread.
    let display_note = paw_plugins::repair_display_env();

    // A script only makes sound if it asks for a device.
    let backend = args
        .audio
        .clone()
        .unwrap_or_else(|| if scripted && !args.doctor { "null" } else { "auto" }.into());
    let mut registry = Registry::with_builtins();
    // Devices written in Lua always run in helpers: Lua must not run on
    // the audio thread.
    if let Ok(exe) = std::env::current_exe() {
        paw_luadev::set_helper(exe, paw_plugins::sandbox::remote);
    }
    // Directories an extension adds are looked in even without the
    // plugins installed on the machine.
    let cache = cache_dir().join("plugins.json");
    registry.set_add_dir(std::rc::Rc::new({
        let cache = cache.clone();
        move |registry, dir| paw_plugins::add_dir(registry, Some(&cache), dir)
    }));
    registry.set_remove_dir(std::rc::Rc::new(paw_plugins::remove_dir));
    registry.set_attach(std::rc::Rc::new(paw_plugins::attach::add));
    let mut plugin_notes = if args.no_plugins {
        Vec::new()
    } else {
        // Each plugin gets a process of its own, started from this program.
        if !args.plugins_in_process
            && let Ok(exe) = std::env::current_exe()
        {
            paw_plugins::sandbox::set_host_command(
                vec![exe.to_string_lossy().into_owned(), "plugin-host".into()],
                Some(&cache),
            );
        }
        let notes = paw_plugins::register(&mut registry, Some(&cache));
        paw_plugins::sandbox::wrap(&mut registry);
        registry.set_rescan(std::rc::Rc::new(move |registry, name| {
            paw_plugins::rescan(registry, Some(&cache), name)
        }));
        notes
    };
    // What the scan said, apart from the note about the display.
    let scanned = plugin_notes.len();
    plugin_notes.extend(display_note);
    let mut kernel = Kernel::new(KernelOpts {
        registry,
        backend: BackendOptions {
            backend,
            sample_rate: args.rate,
            buffer_size: args.buffer,
            input: !args.no_input,
            output_device: args.output.clone(),
            input_device: args.input.clone(),
            test_input: None,
        },
        config_dir: args.config.clone().unwrap_or_else(config_dir),
        runtime_dir: args
            .runtime
            .clone()
            .or_else(|| std::env::var_os("PAW_RUNTIME").map(PathBuf::from)),
        clean: args.clean,
        scripted,
        argv: args.script_args.clone(),
    })?;

    // A panic anywhere but inside a device (which the engine catches, bypasses
    // and reports) writes a safety copy of the project before the program ends.
    let hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        if paw_engine::guard::in_device() {
            return;
        }
        let copy = paw_core::session::panic::write_copy(&info.to_string());
        hook(info);
        if let Some(copy) = copy {
            eprintln!(
                "paw: the unsaved project was kept in {}; `:recover` opens it at the next start",
                copy.display()
            );
        }
    }));
    // What the terminal said about itself, for the log.
    let mut described = None;
    if !scripted && !args.headless {
        // Plugins write to stderr whenever they like, which would land in the
        // middle of the screen.
        quiet_stderr(&cache_dir().join("stderr.log"));
        let sender = kernel.sender();
        let (terminal, width, height) = terminal::Terminal::start(move |event| {
            sender.send(paw_core::KernelMsg::Input(event)).is_ok()
        })?;
        // A panic message printed into the alternate screen would be lost.
        // Only one on the main thread ends the program; a device's is caught.
        let hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            if !paw_engine::guard::in_device() && std::thread::current().name() == Some("main") {
                terminal::restore();
                restore_stderr();
            }
            hook(info);
        }));
        kernel.set_caps(terminal.caps());
        described = Some(terminal.describe());
        kernel.attach(Box::new(terminal), width, height);
    }
    kernel.boot()?;
    if let Some(line) = &described {
        kernel.eval("paw.api.log(...)", &[line])?;
    }
    if !scripted {
        // Opening a project or adding a plugin does not wait for plugins
        // to be made: they come in as they are ready.
        kernel.eval("paw.api.load_apart(true)", &[])?;
    }
    for note in &plugin_notes {
        kernel.eval("paw.api.log('plugin scan: ' .. ...)", &[note])?;
        // Plugin files passed over because they failed before, in one line.
        if note.starts_with("skipped ") {
            kernel.eval("paw.notify(..., 'warn')", &[note])?;
        }
    }
    // The same notes, for the quickfix list's Problems (paw/qf.lua).
    if scanned > 0 {
        let notes: Vec<&str> = plugin_notes[..scanned].iter().map(String::as_str).collect();
        kernel.eval("paw.emit('plugins.scanned', { notes = { ... } })", &notes)?;
    }

    let _server = if scripted || args.no_listen {
        None
    } else {
        let path = args.listen.clone().unwrap_or_else(rpc::default_path);
        match rpc::serve(&path, kernel.sender(), kernel.clients()) {
            Ok(server) => Some(server),
            // The socket is a convenience: carry on without it when it is taken.
            Err(err) if args.listen.is_none() => {
                kernel.eval(
                    "paw.notify(..., 'warn')",
                    &[&format!("no control socket: {err:#}")],
                )?;
                None
            }
            Err(err) => return Err(err),
        }
    };

    if let Some(address) = &args.listen_tcp {
        // Other machines may connect, if they know the token.
        let token_file = args.token_file.clone().unwrap_or_else(rpc::token_path);
        let token = rpc::token_at(&token_file)?;
        let identity = if args.no_tls {
            None
        } else {
            Some(paw_core::tls::identity(&paw_core::tls::default_dir())?)
        };
        let config = identity.as_ref().map(|identity| identity.config.clone());
        let bound = rpc::serve_tcp(address, token, config, kernel.sender(), kernel.clients())?;
        let how = match &identity {
            Some(identity) => format!("in TLS, certificate {}", identity.fingerprint),
            None => "in the clear (--no-tls)".to_string(),
        };
        let note = format!(
            "listening on {bound} for connections that know the token in {}, {how}",
            token_file.display()
        );
        // Without a terminal attached this goes to stderr as well.
        kernel.eval("paw.notify(...)", &[&note])?;
    }

    if let Some(project) = &args.project {
        // A project, or a sound file to start a project from.
        let open = if args.plugins_offline {
            "paw.open(..., { plugins_offline = true })"
        } else {
            "paw.open(...)"
        };
        // One that will not open but has a backup or safety copy starts the
        // program anyway, with those offered (`:recover`).
        kernel.eval(
            &format!(
                "local ok, err = pcall(function(...) {open} end, ...)
                 if not ok and not (paw.autosave and paw.autosave.offered) then error(err, 0) end"
            ),
            &[&project.to_string_lossy()],
        )?;
    } else {
        // Nothing named: `paw.opt.reopen_last` may ask for the last project.
        kernel.eval("paw.recent.reopen_last()", &[])?;
    }
    for expr in &args.exprs {
        kernel.eval(expr, &[])?;
    }
    for keys in &args.keys {
        kernel.eval("paw.keymap.feed(...)", &[keys])?;
    }
    if let Some(script) = &args.script {
        kernel.run_file(script, args.script_args.clone())?;
        return Ok(kernel.exit_code().unwrap_or(0));
    }
    kernel.run()
}

fn main() -> ExitCode {
    let result = run();
    restore_stderr();
    match result {
        Ok(code) => ExitCode::from(code.clamp(0, 255) as u8),
        Err(err) => {
            eprintln!("paw: {err:#}");
            ExitCode::FAILURE
        }
    }
}
