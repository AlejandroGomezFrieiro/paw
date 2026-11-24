//! The command line of `paw`, in clap's derive form.

use std::path::PathBuf;

use clap::{Args, Parser, Subcommand, ValueEnum};

const EXAMPLES: &str = "\
ctl and attach reach the instance on this machine's socket, or on another one with
--socket, or on the network with --connect and a token.

ctl examples:
  paw ctl eval 'return paw.transport.position'
  paw ctl cmd transport.toggle
  paw ctl --json eval 'return paw.project.tempo'
  paw ctl part_add '{\"name\": \"Bass\"}'
  paw ctl --connect studio:7700 --token-file studio.token cmd transport.toggle

In an attached terminal, `:detach` leaves and the instance runs on, and
`:upload <file>` brings a sound file from this machine into the project.";

/// paw: a personal audio workstation
#[derive(Parser, Debug)]
#[command(name = "paw", version, args_conflicts_with_subcommands = true, after_help = EXAMPLES)]
pub(crate) struct Cli {
    #[command(flatten)]
    pub run: Run,
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand, Debug)]
pub(crate) enum Command {
    /// Call a running instance over its socket
    Ctl(Ctl),
    /// Show a running instance's terminal UI here
    Attach(Attach),
    /// Check the audio, MIDI, plugins and environment, and print a report
    Doctor(Box<Doctor>),
    /// Work with MIDI 2.0 clip files (git's textconv for project folders)
    Clip {
        #[command(subcommand)]
        command: ClipCommand,
    },
    /// Work with the chain language, the text form of a chain of devices
    Chain {
        #[command(subcommand)]
        command: ChainCommand,
    },
    /// Hold one plugin in a process of its own (internal)
    #[command(hide = true, disable_help_flag = true)]
    PluginHost(Raw),
    /// Look into one plugin file (internal)
    #[command(hide = true, disable_help_flag = true)]
    PluginScan(Raw),
}

#[derive(Subcommand, Debug)]
pub(crate) enum ClipCommand {
    /// Print a MIDI 2.0 clip file as text, one note to a line
    Cat { file: PathBuf },
}

#[derive(Subcommand, Debug)]
pub(crate) enum ChainCommand {
    /// Print paw's schema of the chain language as JSON: each kind of
    /// device (built-in, plugins and Lua devices), split and modulator
    Schema(Box<ChainSchema>),
}

/// `paw chain schema [options]`: the options of `paw` that decide the
/// kinds of device (`--clean`, `--no-plugins`, `--config`).
#[derive(Args, Debug)]
pub(crate) struct ChainSchema {
    #[command(flatten)]
    pub run: Run,
}

/// Arguments handed on untouched.
#[derive(Args, Debug)]
pub(crate) struct Raw {
    #[arg(num_args = 0.., allow_hyphen_values = true, trailing_var_arg = true)]
    pub args: Vec<String>,
}

/// The options that start a kernel, with or without a terminal.
#[derive(Args, Debug, Default)]
#[expect(
    clippy::struct_excessive_bools,
    reason = "each field is a switch of the command line"
)]
pub(crate) struct Run {
    /// A project (a folder or file), or a sound file to start a project with
    pub project: Option<PathBuf>,
    /// Run a Lua script without a UI, then exit; the rest of the line is its arguments (-l SCRIPT [ARGS]...)
    #[arg(short = 'l', value_name = "SCRIPT", num_args = 1.., allow_hyphen_values = true)]
    pub script: Vec<String>,
    /// Run Lua code after startup (repeatable)
    #[arg(short = 'e', value_name = "LUA", allow_hyphen_values = true)]
    pub exprs: Vec<String>,
    /// Type keys after startup, such as 'jj<Space>'
    #[arg(long, value_name = "KEYS", allow_hyphen_values = true)]
    pub keys: Vec<String>,
    /// Run without a UI until told to quit
    #[arg(long)]
    pub headless: bool,
    /// Skip your configuration and extensions
    #[arg(long)]
    pub clean: bool,
    /// Configuration directory (default: ~/.config/paw)
    #[arg(long, value_name = "DIR")]
    pub config: Option<PathBuf>,
    /// Load the Lua runtime from disk instead of the built-in copy
    #[arg(long, value_name = "DIR")]
    pub runtime: Option<PathBuf>,
    /// Audio backend: auto, null, step (the null backend run by the tests, block by block), pipewire, alsa, jack
    #[arg(long, value_name = "NAME")]
    pub audio: Option<String>,
    /// Sample rate
    #[arg(long, value_name = "HZ")]
    pub rate: Option<u32>,
    /// Frames per audio callback
    #[arg(long, value_name = "N")]
    pub buffer: Option<u32>,
    /// Output device by name or part of it (see :audio)
    #[arg(long, value_name = "NAME")]
    pub output: Option<String>,
    /// Input device by name or part of it
    #[arg(long, value_name = "NAME")]
    pub input: Option<String>,
    /// Do not open the audio device's input
    #[arg(long)]
    pub no_input: bool,
    /// Schedule time for timers and delays: wall, or manual for tests
    /// (it moves only when a script waits)
    #[arg(long, value_enum, value_name = "CLOCK", default_value_t)]
    pub clock: ClockChoice,
    /// Control socket path (default: $XDG_RUNTIME_DIR/paw.sock)
    #[arg(long, value_name = "PATH")]
    pub listen: Option<PathBuf>,
    /// Do not open a control socket
    #[arg(long)]
    pub no_listen: bool,
    /// Also take connections from the network, on host:port (127.0.0.1:7700;
    /// 0.0.0.0:7700 for any machine that knows the token), in TLS with a
    /// certificate made the first time
    #[arg(long, value_name = "ADDRESS")]
    pub listen_tcp: Option<String>,
    /// Take them in the clear instead: for a network you trust
    #[arg(long)]
    pub no_tls: bool,
    /// Where the token for network connections is kept (default:
    /// ~/.local/state/paw/token, made if missing)
    #[arg(long, value_name = "PATH")]
    pub token_file: Option<PathBuf>,
    /// Do not look for CLAP, LV2 and VST3 plugins
    #[arg(long)]
    pub no_plugins: bool,
    /// Load plugins into this process, not each into its own
    #[arg(long)]
    pub plugins_in_process: bool,
    /// Open the project with every plugin offline (:plugins.online)
    #[arg(long)]
    pub plugins_offline: bool,
    /// Write the time of each step of the start to FILE, as Neovim's --startuptime
    #[arg(long, value_name = "FILE")]
    pub startuptime: Option<PathBuf>,
}

impl Run {
    pub(crate) fn script_path(&self) -> Option<PathBuf> {
        self.script.first().map(PathBuf::from)
    }

    pub(crate) fn script_args(&self) -> Vec<String> {
        self.script.iter().skip(1).cloned().collect()
    }
}

/// Where `ctl` and `attach` find the instance.
#[derive(Args, Debug, Default)]
#[command(next_help_heading = "Connection")]
pub(crate) struct Connect {
    /// Another socket
    #[arg(long, value_name = "PATH")]
    pub socket: Option<PathBuf>,
    /// An instance listening on the network
    #[arg(long, value_name = "HOST:PORT")]
    pub connect: Option<String>,
    /// The token for --connect (or $PAW_TOKEN)
    #[arg(long, value_name = "TOKEN")]
    pub token: Option<String>,
    /// A file that holds the token
    #[arg(long, value_name = "PATH")]
    pub token_file: Option<PathBuf>,
    /// Take the certificate it shows though another was remembered for it
    #[arg(long)]
    pub accept_certificate: bool,
    /// Connect in the clear, to one started with --no-tls
    #[arg(long)]
    pub no_tls: bool,
}

/// `paw ctl [--json] <method> [params...]`
#[derive(Args, Debug)]
pub(crate) struct Ctl {
    #[command(flatten)]
    pub connect: Connect,
    /// Print one line of JSON, {"ok": ..., "result": ...}, whatever happens
    #[arg(long)]
    pub json: bool,
    /// The method to call
    pub method: String,
    /// Each parameter is JSON, or a plain string when it is not
    #[arg(num_args = 0.., allow_hyphen_values = true, trailing_var_arg = true)]
    pub params: Vec<String>,
}

#[derive(Args, Debug, Default)]
pub(crate) struct Attach {
    #[command(flatten)]
    pub connect: Connect,
    /// Play the instance's sound on this machine (about 1 Mbit/s)
    #[arg(long)]
    pub listen_audio: bool,
    /// Write the instance's sound to a file
    #[arg(long, value_name = "FILE.WAV")]
    pub listen_audio_to: Option<PathBuf>,
}

/// `paw doctor [options]`: the options of `paw` too.
#[derive(Args, Debug)]
pub(crate) struct Doctor {
    #[command(flatten)]
    pub run: Run,
    /// Length of the dropout runs
    #[arg(long, value_name = "N")]
    pub seconds: Option<String>,
    /// A plugin to test (repeatable)
    #[arg(long, value_name = "NAME")]
    pub plugin: Vec<String>,
    /// Only these checks (comma separated)
    #[arg(long, value_name = "IDS")]
    pub only: Option<String>,
}

impl Doctor {
    /// The options the report script takes, as `--seconds=20`.
    pub(crate) fn script_args(&self) -> Vec<String> {
        let mut own = Vec::new();
        if let Some(seconds) = &self.seconds {
            own.push(format!("--seconds={seconds}"));
        }
        own.extend(self.plugin.iter().map(|p| format!("--plugin={p}")));
        if let Some(only) = &self.only {
            own.push(format!("--only={only}"));
        }
        own
    }
}

/// The schedule clock of the process (`--clock`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ValueEnum)]
pub(crate) enum ClockChoice {
    /// Schedule time is the time on the wall.
    #[default]
    Wall,
    /// Schedule time moves only when a script waits (`paw.wait`): for tests.
    Manual,
}
