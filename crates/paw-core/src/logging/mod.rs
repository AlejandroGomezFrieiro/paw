//! The log of paw (ADR 0043): one subscriber of `tracing` that only the
//! program installs ([`init`]), and one layer that does these jobs:
//!
//! - A session writes `paw.log` in the state folder, at `info` and above
//!   unless `PAW_LOG` or `paw.opt.loglevel` says otherwise. The folder
//!   keeps 5 runs ([`file`]).
//! - The flight recorder keeps the last events of `debug` and above in
//!   memory ([`recorder`]). An error, a panic and `:log dump` write the
//!   events that the file left out.
//! - A script, a client process and a session with no terminal write
//!   their warnings and errors to the standard error.
//!
//! The audio thread never logs: it keeps counters, and the kernel thread
//! logs them (`kernel/audio_watch.rs`).

mod file;
mod recorder;

use std::cell::Cell;
use std::fmt::Write as _;
use std::io::Write as _;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard, OnceLock, PoisonError};

use tracing::field::{Field, Visit};
use tracing::subscriber::Interest;
use tracing::{Event, Level, Metadata, Subscriber};
use tracing_subscriber::filter::Targets;
use tracing_subscriber::layer::{Context, Layer, SubscriberExt as _};

use file::LogFile;
use recorder::Recorder;

/// What kind of process logs, which decides where the lines go.
pub enum Run {
    /// A session (the terminal or `--headless`): `paw.log` in `state`, at
    /// `info`. `stderr_log` is the file that takes descriptors 1 and 2
    /// while the terminal shows paw (ADR 0042): its text goes into the log
    /// of its run at the next start.
    Session { state: PathBuf, stderr_log: PathBuf },
    /// A script (`-l`), `paw doctor`, `paw chain schema`, and the client
    /// processes (`paw attach`, `paw ctl`, the plugin host): no file, and
    /// `warn` and above to the standard error.
    Script,
}

/// How [`init`] sets up the log.
pub struct Options {
    pub run: Run,
    /// The levels that `PAW_LOG` gives, if it is set. It wins over
    /// `paw.opt.loglevel` for this run.
    pub env_filter: Option<String>,
    /// The home folder: a path under it is written with `~`.
    pub home: Option<PathBuf>,
}

/// The files of the log, for `:log`. Each is `None` in a run with no file.
#[derive(Debug, Default, Clone, serde::Serialize)]
pub struct Files {
    /// `paw.log`: this run.
    pub current: Option<PathBuf>,
    /// `paw.log.1`: the run before.
    pub previous: Option<PathBuf>,
    /// `stderr.log`: what other code prints in this run.
    pub stderr: Option<PathBuf>,
}

/// Where the warnings and errors also go, as text without the time.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Echo {
    /// Nowhere: the terminal shows paw, and descriptor 2 is `stderr.log`.
    Off,
    /// The standard error, at `warn` and above.
    Warnings,
    /// The standard error, at the levels of the filter (a script).
    Filter,
}

/// The state of the log, behind the lock of [`Book`].
struct State {
    filter: Targets,
    /// The text of `filter`, as `paw.api.log_level` gives it back.
    filter_text: String,
    /// `PAW_LOG` set the filter: `paw.opt.loglevel` does not change it.
    from_env: bool,
    echo: Echo,
    file: Option<LogFile>,
    recorder: Recorder,
    /// The home folder as text, without a slash at the end.
    home: Option<String>,
    files: Files,
}

/// The log that the layer writes and that the kernel asks.
pub(crate) struct Book {
    state: Mutex<State>,
}

/// The book of the subscriber that [`init`] installed.
static BOOK: OnceLock<Arc<Book>> = OnceLock::new();

thread_local! {
    /// Set while this thread writes an event: an event that the writing
    /// makes (a panic in it, for example) is dropped, not written into a
    /// lock that this thread holds.
    static WRITING: Cell<bool> = const { Cell::new(false) };
}

/// The filter that a session starts with.
const SESSION_LEVEL: &str = "info";
/// The filter that a script starts with.
const SCRIPT_LEVEL: &str = "warn";

/// Install the subscriber of the program. A session rotates the runs in
/// its state folder first. Returns a note for the user when a part did not
/// start (a log file that cannot be written, a `PAW_LOG` that does not
/// parse); the log works on without that part.
pub fn init(options: Options) -> Option<String> {
    let (book, note) = Book::new(options);
    let book = Arc::new(book);
    let subscriber = tracing_subscriber::registry().with(PawLayer { book: book.clone() });
    // A second call keeps the first subscriber, as a test that starts the
    // kernel twice does.
    if tracing::subscriber::set_global_default(subscriber).is_ok() {
        let _ = BOOK.set(book);
    }
    note
}

impl Book {
    fn new(options: Options) -> (Self, Option<String>) {
        let mut notes = Vec::new();
        let (default, echo) = match &options.run {
            Run::Session { .. } => (SESSION_LEVEL, Echo::Warnings),
            Run::Script => (SCRIPT_LEVEL, Echo::Filter),
        };
        let mut from_env = false;
        let mut filter_text = default.to_string();
        if let Some(given) = &options.env_filter {
            match given.parse::<Targets>() {
                Ok(_) => {
                    filter_text.clone_from(given);
                    from_env = true;
                }
                Err(err) => notes.push(format!("PAW_LOG={given} is not a list of levels ({err}): the log keeps {default}")),
            }
        }
        let mut files = Files::default();
        let file = match &options.run {
            Run::Session { state, stderr_log } => {
                let opened = file::rotate(state, Some(stderr_log)).and_then(|()| LogFile::create(state));
                match opened {
                    Ok(log) => {
                        files = Files {
                            current: Some(file::run_path(state, 0)),
                            previous: Some(file::run_path(state, 1)),
                            stderr: Some(stderr_log.clone()),
                        };
                        Some(log)
                    }
                    Err(err) => {
                        notes.push(format!("no log file in {}: {err}", state.display()));
                        None
                    }
                }
            }
            Run::Script => None,
        };
        let home = options
            .home
            .map(|home| home.to_string_lossy().trim_end_matches('/').to_string())
            .filter(|home| !home.is_empty());
        let state = State {
            filter: filter_text.parse().unwrap_or_default(),
            filter_text,
            from_env,
            echo,
            file,
            recorder: Recorder::default(),
            home,
            files,
        };
        let note = (!notes.is_empty()).then(|| notes.join("; "));
        (Self { state: Mutex::new(state) }, note)
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        // A panic while the lock was held leaves the state usable: each
        // write is whole or absent.
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// The book of the program, if [`init`] installed one.
fn book() -> Option<&'static Book> {
    BOOK.get().map(|book| &**book)
}

/// What a change of the levels did.
#[derive(Debug, PartialEq, Eq)]
pub enum LevelChange {
    /// The new levels apply.
    Set,
    /// `PAW_LOG` set the levels of this run: they stay.
    KeptEnv(String),
}

/// Check the levels `spec` (`info`, `info,plugin=debug`). The error says
/// what is wrong.
pub fn check_levels(spec: &str) -> Result<(), String> {
    spec.parse::<Targets>().map(|_| ()).map_err(|err| format!("{spec:?} is not a list of levels such as \"info,plugin=debug\": {err}"))
}

/// Set the levels of the file (and of the standard error of a script), as
/// `paw.opt.loglevel` asks. `PAW_LOG` wins.
pub fn set_levels(spec: &str) -> Result<LevelChange, String> {
    let filter: Targets = spec.parse().map_err(|err| format!("{spec:?} is not a list of levels: {err}"))?;
    let Some(book) = book() else { return Ok(LevelChange::Set) };
    let mut state = book.lock();
    if state.from_env {
        return Ok(LevelChange::KeptEnv(state.filter_text.clone()));
    }
    state.filter = filter;
    spec.clone_into(&mut state.filter_text);
    Ok(LevelChange::Set)
}

/// The levels that apply now, as text.
pub fn levels() -> String {
    book().map_or_else(|| SCRIPT_LEVEL.to_string(), |book| book.lock().filter_text.clone())
}

/// Where the warnings also go: [`Echo::Off`] while the terminal shows paw.
pub fn set_echo(echo: Echo) {
    if let Some(book) = book() {
        book.lock().echo = echo;
    }
}

/// The files of the log.
pub fn files() -> Files {
    book().map(|book| book.lock().files.clone()).unwrap_or_default()
}

/// Write the events of the flight recorder that the file left out, since
/// the last dump. Returns how many, or `None` in a run with no file.
pub fn dump(reason: &str) -> Option<usize> {
    let book = book()?;
    let mut state = book.lock();
    state.file.as_ref()?;
    Some(state.dump(&now(), reason))
}

/// An event of target `lua` (`paw.api.log`, `paw.notify`) at `level`.
pub fn lua(level: Level, text: &str) {
    match level {
        Level::ERROR => tracing::error!(target: "lua", "{text}"),
        Level::WARN => tracing::warn!(target: "lua", "{text}"),
        Level::INFO => tracing::info!(target: "lua", "{text}"),
        Level::DEBUG => tracing::debug!(target: "lua", "{text}"),
        Level::TRACE => tracing::trace!(target: "lua", "{text}"),
    }
}

/// The level that a word names: `error`, `warn`, `info`, `debug`, `trace`.
pub fn level_of(word: &str) -> Option<Level> {
    word.parse().ok()
}

/// A panic that no part of paw catches: its message and its backtrace, as
/// an error of target `panic`, after the flight recorder.
pub fn panic(message: &str) {
    let backtrace = std::backtrace::Backtrace::force_capture();
    tracing::error!(target: "panic", "{message}\n{backtrace}");
}

/// The time of a line: UTC, to the millisecond.
fn now() -> String {
    jiff::Timestamp::now().strftime("%Y-%m-%d %H:%M:%S%.3f").to_string()
}

impl State {
    /// Take one event: the file, the ring, the standard error, and a dump
    /// before an error.
    fn take(&mut self, time: &str, level: Level, target: &str, message: &str) {
        let message = self.tilde(message);
        let body = format!("{level:<5} {target}: {message}");
        // The detail before an error comes before it in the file.
        if level == Level::ERROR && self.file.is_some() {
            self.dump(time, "error");
        }
        let wanted = self.filter.would_enable(target, &level);
        let in_file = wanted && self.file.as_mut().is_some_and(|file| file.line(time, &body));
        self.recorder.push(format!("{time} {body}"), in_file);
        if self.echoes(level, target, wanted) {
            // The standard error that cannot be written cannot say so.
            let _ = writeln!(std::io::stderr().lock(), "{message}");
        }
    }

    /// Whether an event goes to the standard error. `paw.notify` writes its
    /// own line there, so the target `lua` never does.
    fn echoes(&self, level: Level, target: &str, wanted: bool) -> bool {
        target != "lua"
            && match self.echo {
                Echo::Off => false,
                Echo::Warnings => level <= Level::WARN,
                Echo::Filter => wanted,
            }
    }

    fn dump(&mut self, time: &str, reason: &str) -> usize {
        let Some(file) = self.file.as_mut() else { return 0 };
        let lines = self.recorder.take_undumped();
        let count = lines.len();
        if count > 0 {
            let header = format!("flight recorder: the {count} events before this {reason} that the file left out");
            file.dump(time, &header, lines.into_iter());
        }
        count
    }

    /// `text` with each path under the home folder written from `~`.
    fn tilde(&self, text: &str) -> String {
        let Some(home) = &self.home else { return text.to_string() };
        let mut out = String::with_capacity(text.len());
        let mut rest = text;
        while let Some(at) = rest.find(home.as_str()) {
            let after = &rest[at + home.len()..];
            out.push_str(&rest[..at]);
            // `/home/al` is not the home of `/home/alex`.
            if after.is_empty() || after.starts_with('/') {
                out.push('~');
            } else {
                out.push_str(home);
            }
            rest = after;
        }
        out.push_str(rest);
        out
    }
}

/// The layer of paw in the subscriber.
struct PawLayer {
    book: Arc<Book>,
}

impl<S: Subscriber> Layer<S> for PawLayer {
    fn register_callsite(&self, _: &'static Metadata<'static>) -> Interest {
        // The levels change at run time: ask `enabled` each time.
        Interest::sometimes()
    }

    fn enabled(&self, metadata: &Metadata<'_>, _: Context<'_, S>) -> bool {
        // The flight recorder takes `debug` and above of each target.
        *metadata.level() <= Level::DEBUG || self.book.lock().filter.would_enable(metadata.target(), metadata.level())
    }

    fn on_event(&self, event: &Event<'_>, _: Context<'_, S>) {
        let Some(_writing) = Writing::start() else { return };
        let mut message = Message::default();
        event.record(&mut message);
        let metadata = event.metadata();
        self.book.lock().take(&now(), *metadata.level(), metadata.target(), &message.0);
    }
}

/// [`WRITING`] while it lives, also when the write panics.
struct Writing;

impl Writing {
    /// `None` when this thread writes an event already.
    fn start() -> Option<Self> {
        (!WRITING.with(|writing| writing.replace(true))).then_some(Self)
    }
}

impl Drop for Writing {
    fn drop(&mut self) {
        WRITING.with(|writing| writing.set(false));
    }
}

/// The text of an event: its message, then each other field as `name=value`.
#[derive(Default)]
struct Message(String);

impl Visit for Message {
    fn record_str(&mut self, field: &Field, value: &str) {
        if field.name() == "message" {
            self.0.insert_str(0, value);
        } else {
            let _ = write!(self.0, " {}={value}", field.name());
        }
    }

    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.0.insert_str(0, &format!("{value:?}"));
        } else {
            let _ = write!(self.0, " {}={value:?}", field.name());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    /// A session's book in `dir`, and a subscriber over it for `body`.
    fn session(dir: &Path, env_filter: Option<&str>, body: impl FnOnce(&Arc<Book>)) {
        let (book, note) = Book::new(Options {
            run: Run::Session { state: dir.to_path_buf(), stderr_log: dir.join("stderr.log") },
            env_filter: env_filter.map(str::to_string),
            home: Some(PathBuf::from("/srv/someone")),
        });
        assert_eq!(note, None);
        let book = Arc::new(book);
        let subscriber = tracing_subscriber::registry().with(PawLayer { book: book.clone() });
        tracing::subscriber::with_default(subscriber, || body(&book));
    }

    fn log_text(dir: &Path) -> String {
        std::fs::read_to_string(file::run_path(dir, 0)).unwrap()
    }

    #[test]
    fn the_file_takes_info_and_the_recorder_writes_the_rest_on_an_error() {
        let dir = tempfile::tempdir().unwrap();
        session(dir.path(), None, |_| {
            tracing::debug!(target: "plugin", "a detail");
            tracing::info!(target: "undo", "step 1: add note");
            tracing::error!("it broke in /srv/someone/song");
        });
        let text = log_text(dir.path());
        let lines: Vec<&str> = text.lines().map(|line| &line[24..]).collect();
        assert_eq!(
            lines,
            [
                "INFO  undo: step 1: add note",
                "---- flight recorder: the 1 events before this error that the file left out ----",
                "DEBUG plugin: a detail",
                "---- the end of the flight recorder ----",
                "ERROR paw_core::logging::tests: it broke in ~/song",
            ],
            "{text}"
        );
    }

    #[test]
    fn the_levels_change_per_target_and_paw_log_wins() {
        let dir = tempfile::tempdir().unwrap();
        session(dir.path(), None, |book| {
            book.lock().filter = "warn,plugin=debug".parse().unwrap();
            tracing::debug!(target: "plugin", "shown");
            tracing::info!(target: "undo", "hidden");
        });
        let text = log_text(dir.path());
        assert!(text.contains("DEBUG plugin: shown") && !text.contains("hidden"), "{text}");

        let dir = tempfile::tempdir().unwrap();
        session(dir.path(), Some("error"), |book| {
            tracing::warn!("hidden");
            assert!(book.lock().from_env);
        });
        assert!(!log_text(dir.path()).contains("hidden"));
    }

    #[test]
    fn a_word_is_a_level_and_a_wrong_list_is_refused() {
        assert_eq!(level_of("warn"), Some(Level::WARN));
        assert_eq!(level_of("loud"), None);
        assert!(check_levels("info,plugin=debug").is_ok());
        assert!(check_levels("info,plugin=loud").is_err());
    }
}
