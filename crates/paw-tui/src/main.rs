//! The `paw` command: start the kernel with a terminal UI, without one, to run
//! a script, or to talk to an instance that is already running.

#![warn(clippy::undocumented_unsafe_blocks)]

mod args;
mod graphics;
mod keys;
mod terminal;

use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use args::{Attach, Cli, ClipCommand, Command, Connect, Ctl};
use clap::Parser;
use paw_core::{Kernel, KernelOpts, rpc, startuptime};
use paw_engine::Registry;
use paw_engine::backend::{BackendChoice, BackendOptions};
use serde_json::Value;

fn config_dir() -> PathBuf {
    let base = paw_proto::dirs::config().unwrap_or_else(|| PathBuf::from("."));
    base.join("paw")
}

/// The terminal's stderr, kept while fd 2 points at a log file.
static REAL_STDERR: std::sync::Mutex<Option<std::os::fd::OwnedFd>> = std::sync::Mutex::new(None);

/// Send everything written to stderr into a file instead of the terminal.
fn quiet_stderr(log: &std::path::Path) {
    if let Some(dir) = log.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let Ok(file) = std::fs::File::create(log) else {
        return;
    };
    let Ok(saved) = rustix::io::dup(rustix::stdio::stderr()) else {
        return;
    };
    // Descriptor 2 is replaced on purpose; the old one is saved first.
    if rustix::stdio::dup2_stderr(&file).is_ok() {
        *REAL_STDERR.lock().unwrap_or_else(|e| e.into_inner()) = Some(saved);
    }
}

/// Undo [`quiet_stderr`], so that a final error message reaches the terminal.
fn restore_stderr() {
    let saved = REAL_STDERR.lock().unwrap_or_else(|e| e.into_inner()).take();
    if let Some(saved) = saved {
        // Dropping `saved` closes the duplicate `quiet_stderr` made, once.
        let _ = rustix::stdio::dup2_stderr(&saved);
    }
}

fn cache_dir() -> PathBuf {
    let base = paw_proto::dirs::cache().unwrap_or_else(std::env::temp_dir);
    base.join("paw")
}

/// Connect to the instance `ctl` and `attach` are pointed at.
fn connect(options: &Connect) -> Result<rpc::Connection> {
    let socket = options.socket.clone().unwrap_or_else(rpc::default_path);
    let address = options.connect.clone();
    let mut token = std::env::var("PAW_TOKEN").ok();
    let mut wire = if options.no_tls { rpc::Wire::Plain } else { rpc::Wire::default() };
    let accept_new = options.accept_certificate;
    if let Some(path) = &options.token_file {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("reading the token in {}", path.display()))?;
        token = Some(text.trim().to_string());
    }
    if let Some(given) = &options.token {
        token = Some(given.clone());
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
fn ctl(call: Ctl) -> Result<()> {
    let outcome = ctl_call(&call);
    if !call.json {
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

fn ctl_call(call: &Ctl) -> Result<Value> {
    let mut connection = connect(&call.connect)?;
    let params: Vec<Value> = call
        .params
        .iter()
        .map(|p| serde_json::from_str(p).unwrap_or_else(|_| Value::String(p.clone())))
        .collect();
    connection.call(&call.method, Value::Array(params))
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
fn attach(options: &Attach) -> Result<()> {
    let hear = match (&options.listen_audio_to, options.listen_audio) {
        (Some(file), _) => Some(Hear::File(file.clone())),
        (None, true) => Some(Hear::Device),
        (None, false) => None,
    };
    let mut connection = connect(&options.connect)?;
    // What was typed and what the instance sends come in on one channel,
    // so that the loop sleeps until there is one or the other.
    let (incoming, arrived) = std::sync::mpsc::channel();
    let typed = incoming.clone();
    let (mut screen, width, height) =
        terminal::Terminal::start(move |event| typed.send(Incoming::Typed(event)).is_ok())?;
    let events = std::mem::replace(&mut connection.events, std::sync::mpsc::channel().1);
    // Ends when the connection does (its reader drops the sender) or when
    // this function returns (the channel's receiver is gone).
    std::thread::Builder::new()
        .name("paw-attach".into())
        .spawn(move || {
            for (name, payload) in events {
                if incoming.send(Incoming::Sent(name, payload)).is_err() {
                    return;
                }
            }
            let _ = incoming.send(Incoming::Ended);
        })
        .context("starting the thread that waits for the instance")?;
    connection.call("ui.attach", serde_json::json!([width, height, screen.caps().to_json()]))?;
    let mut player = None;
    if hear.is_some() {
        listen(&mut connection, &mut player, hear.as_ref());
    }
    let mut grid = paw_core::grid::Grid::new(width, height);
    use paw_core::Frontend;
    // What was typed goes out; what the instance shows comes in.
    for arrival in arrived {
        match arrival {
            Incoming::Typed(event) => {
                connection.notify("ui.input", serde_json::json!([paw_core::remote::input_json(&event)]))?;
            }
            Incoming::Sent(name, payload) => match name.as_str() {
                "ui.grid" => {
                    let cursor = paw_core::remote::apply(&mut grid, &payload)?;
                    fetch_pixels(&mut connection, &grid);
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
            },
            // The instance ended, or the connection did.
            Incoming::Ended => return Ok(()),
        }
    }
    Ok(())
}

/// What an attached terminal waits for: a key or the mouse here, an event
/// from the instance, or the end of the connection.
enum Incoming {
    Typed(paw_core::InputEvent),
    Sent(String, Value),
    Ended,
}

/// Ask the instance once for each picture of pixels (`paw.canvas.image`)
/// that the strips name and this side does not keep: the pixels are made
/// there, the drawing names them by key.
fn fetch_pixels(connection: &mut rpc::Connection, grid: &paw_core::grid::Grid) {
    use paw_raster::pixels;
    for surface in &grid.surfaces {
        for key in pixels::keys_in(&surface.ops) {
            if pixels::get(key).is_none()
                && let Some(pixmap) = connection.call("scene.pixels", serde_json::json!([key])).ok().as_ref().and_then(pixels::from_blob)
            {
                pixels::keep_as(key, pixmap);
            }
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
fn clip_cat(file: &std::path::Path) -> Result<()> {
    let bytes = std::fs::read(file).with_context(|| format!("reading {}", file.display()))?;
    let clip = paw_core::clipfile::decode(&bytes).with_context(|| file.display().to_string())?;
    print!("{}", paw_core::clipfile::text(&clip));
    Ok(())
}

/// What the command line asks for after the subcommands that finish at once.
enum Start {
    /// A subcommand ran; this is the exit code.
    Done(i32),
    /// Start the kernel; the flag is `paw doctor`.
    Kernel(Box<args::Run>, bool),
}

/// Run the subcommands that need no kernel, or pick the options to start one.
fn dispatch(cli: Cli) -> Result<Start> {
    Ok(match cli.command {
        None => Start::Kernel(Box::new(cli.run), false),
        Some(Command::Clip { command: ClipCommand::Cat { file } }) => {
            clip_cat(&file)?;
            Start::Done(0)
        }
        Some(Command::Ctl(call)) => {
            ctl(call)?;
            Start::Done(0)
        }
        Some(Command::Attach(options)) => {
            let result = attach(&options);
            terminal::restore();
            result?;
            Start::Done(0)
        }
        // Started by a running instance to hold one plugin, or to look into
        // one plugin file, in a process of its own.
        Some(Command::PluginHost(raw)) => {
            let args = raw.args;
            // A device written in Lua is held the way a plugin is.
            if args.first().is_some_and(|kind| kind.starts_with("lua:")) {
                // SAFETY: This process is the helper that the DAW's sandbox started: the socket and the
                // memory named in `args` are descriptors it inherited and that only these calls take,
                // and no thread has started yet (`main` has only parsed its arguments).
                return Ok(Start::Done(unsafe {
                    paw_plugins::sandbox::serve_with(&args, |_, rate, block| {
                        paw_luadev::serve_make(rate, block)
                    })
                }));
            }
            // SAFETY: As above.
            Start::Done(unsafe { paw_plugins::sandbox::serve(&args) })
        }
        Some(Command::PluginScan(raw)) => {
            let args = raw.args;
            if args.first().map(String::as_str) == Some("lua") {
                return Ok(Start::Done(paw_luadev::scan_main(&args[1..])));
            }
            Start::Done(paw_plugins::scan_main(&args))
        }
        Some(Command::Doctor(doctor)) => {
            let own = doctor.script_args();
            let mut run = doctor.run;
            run.script = std::iter::once(doctor_script()?.to_string_lossy().into_owned())
                .chain(own)
                .collect();
            Start::Kernel(Box::new(run), true)
        }
    })
}

/// A project that a running paw has open: this terminal joins it as a
/// new seat, so that two people edit the one project, not two copies.
fn join_running(args: &args::Run, scripted: bool) -> Result<bool> {
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
        let result = attach(&Attach::default());
        terminal::restore();
        result?;
        return Ok(true);
    }
    Ok(false)
}

/// The registry of devices, with the plugin scan. Returns the scan's notes
/// and how many of them come from the scan itself.
fn build_registry(args: &args::Run, display_note: Option<String>) -> (Registry, Vec<String>, usize) {
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
    (registry, plugin_notes, scanned)
}

/// A panic anywhere but inside a device (which the engine catches, bypasses
/// and reports) writes a safety copy of the project before the program ends.
fn install_safety_copy_hook() {
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
}

/// Start the terminal and attach it to the kernel. Returns what the terminal
/// said about itself, for the log.
fn attach_terminal(kernel: &mut Kernel) -> Result<String> {
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
    let described = terminal.describe();
    kernel.attach(Box::new(terminal), width, height);
    Ok(described)
}

/// Tell the log, the notifications and the quickfix list what the plugin
/// scan said. `scanned` notes come from the scan, the rest from elsewhere.
fn report_plugin_notes(kernel: &mut Kernel, plugin_notes: &[String], scanned: usize) -> Result<()> {
    for note in plugin_notes {
        kernel.eval("paw.api.log('plugin scan: ' .. ...)", &[note])?;
        // Plugin files passed over because they failed before, in one line.
        if note.starts_with("skipped ") {
            kernel.eval("paw.notify(..., 'warn')", &[note])?;
        }
    }
    // The same notes, for the quickfix list's Problems (paw/qf.tl).
    if scanned > 0 {
        let notes: Vec<&str> = plugin_notes[..scanned].iter().map(String::as_str).collect();
        kernel.eval("paw.emit('plugins.scanned', { notes = { ... } })", &notes)?;
    }
    Ok(())
}

/// The control socket, and the TCP listener if asked for. The returned
/// server must live as long as the kernel runs.
fn serve_listeners(args: &args::Run, scripted: bool, kernel: &mut Kernel) -> Result<Option<rpc::Server>> {
    let server = if scripted || args.no_listen {
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
        listen_tcp(args, address, kernel)?;
    }
    Ok(server)
}

/// Other machines may connect to `address`, if they know the token.
fn listen_tcp(args: &args::Run, address: &str, kernel: &mut Kernel) -> Result<()> {
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
    Ok(())
}

/// Open the project named on the command line, or the last one, then run the
/// expressions and keys that were passed.
fn open_and_feed(args: &args::Run, kernel: &mut Kernel) -> Result<()> {
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
    startuptime::event(if args.project.is_some() { "open the project" } else { "reopen the last project" });
    for expr in &args.exprs {
        kernel.eval(expr, &[])?;
    }
    for keys in &args.keys {
        kernel.eval("paw.keymap.feed(...)", &[keys])?;
    }
    if !args.exprs.is_empty() || !args.keys.is_empty() {
        startuptime::event("-e and --keys");
    }
    Ok(())
}

fn run() -> Result<i32> {
    let (args, doctor) = match dispatch(Cli::parse())? {
        Start::Done(code) => return Ok(code),
        Start::Kernel(args, doctor) => (*args, doctor),
    };
    if let Some(file) = &args.startuptime {
        startuptime::start(file);
    }
    // paw-gui starts the kernel with `--listen`: a kernel that would not
    // listen must stop at once rather than leave it waiting for the socket.
    if args.no_listen && args.listen.is_some() {
        bail!("--no-listen and --listen contradict each other (the window always talks to the kernel through a socket)");
    }
    let script = args.script_path();
    let script_args = args.script_args();
    let scripted = script.is_some();
    if join_running(&args, scripted)? {
        return Ok(0);
    }
    // A terminal older than the display it names cannot open a plugin's
    // window. Put that right while this is still the only thread.
    // SAFETY: Called from `main` before any thread starts: only the arguments were parsed and, at
    // most, a running paw asked over its socket, so nothing else reads or writes the environment.
    let display_note = unsafe { paw_plugins::repair_display_env() };

    // A script only makes sound if it asks for a device.
    let backend = match args.audio.as_deref() {
        Some(word) => BackendChoice::from(word),
        None if scripted && !doctor => BackendChoice::Null,
        None => BackendChoice::Auto,
    };
    let (registry, plugin_notes, scanned) = build_registry(&args, display_note);
    startuptime::event(if args.no_plugins { "devices" } else { "devices, the plugin scan" });
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
        argv: script_args.clone(),
    })?;

    startuptime::event("kernel, engine, audio device");
    install_safety_copy_hook();
    let described = if !scripted && !args.headless {
        Some(attach_terminal(&mut kernel)?)
    } else {
        None
    };
    if described.is_some() {
        startuptime::event("terminal");
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
    report_plugin_notes(&mut kernel, &plugin_notes, scanned)?;
    let _server = serve_listeners(&args, scripted, &mut kernel)?;
    startuptime::event("plugin notes, control socket");
    open_and_feed(&args, &mut kernel)?;
    if let Some(script) = &script {
        kernel.startup_done("the script starts");
        kernel.run_file(script, script_args)?;
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
