//! Devices written in Lua, in the spirit of REAPER's JSFX: a file with
//! parameters and a `process` function, made with `paw.dsp`
//! (runtime/lua/paw/dsp.lua), that shows among the devices as `lua:<name>`.
//!
//! LuaJIT allocates as it runs and the audio thread must not, so a Lua
//! device never runs in the engine's process. Each instance gets a helper
//! process of its own, the same one plugins get (`paw_plugins::sandbox`):
//! the engine hands it each block through shared memory and waits for it
//! within the block, so it adds no latency, and a script that fails, hangs
//! or crashes is stopped alone and shown as stopped. In the helper the
//! script has a Lua state to itself, and works on the block in `ffi`
//! arrays, which LuaJIT compiles.
//!
//! Scripts are found in directories: `devices` in the configuration
//! directory and in each extension. What a script is (its name, kind and
//! parameters) is learnt by loading it in a helper too, and again whenever
//! the file changes.

pub mod device;

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::ExitStatus;
use std::rc::Rc;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant, UNIX_EPOCH};

use anyhow::{Context, Result};
use paw_engine::device::{DeviceFactory, DeviceFormat, DeviceInfo, Instance};
use paw_engine::Registry;

pub use device::{Descriptor, describe, make};

/// Makes a factory whose devices run in helper processes: the device's
/// description, the helper's command, and what to add to its environment.
pub type Remote = fn(DeviceInfo, Vec<String>, Vec<(String, String)>) -> Rc<dyn DeviceFactory>;

/// This program, to start helpers from, and how to make their factories.
static HELPER: OnceLock<(PathBuf, Remote)> = OnceLock::new();

/// What tells a helper which script to run.
const SCRIPT_ENV: &str = "PAW_LUA_DEVICE";

/// How long looking into scripts may take before the helper doing it is ended.
const SCAN_LIMIT: Duration = Duration::from_secs(30);

/// Why a script could not be looked into. Its text is what `paw.api`
/// shows as the script's error.
#[derive(Debug, Clone, thiserror::Error)]
pub enum ScanError {
    /// The script did not load: why, as the helper (or Lua) said it.
    #[error("{0}")]
    Script(String),
    /// The helper could not be started or watched.
    #[error("{0}")]
    Helper(#[source] Arc<std::io::Error>),
    /// The helper did not finish in time and was ended.
    #[error("looking into it took over {} seconds", SCAN_LIMIT.as_secs())]
    Hung,
    /// The helper ended without an answer.
    #[error("looking into it failed ({0})")]
    Failed(ExitStatus),
    /// The helper answered for another number of scripts.
    #[error("looking into it gave a wrong answer")]
    WrongAnswer,
}

impl From<std::io::Error> for ScanError {
    fn from(err: std::io::Error) -> Self {
        Self::Helper(Arc::new(err))
    }
}

/// What a helper prints for each script: the description, or why it did
/// not load. The wire between `plugin-scan lua` and [`describe_all`].
type ScanAnswer = Result<Descriptor, String>;

/// Say how to run Lua devices apart: `exe` is this program, which runs one
/// as `plugin-host lua:<name>` and looks into scripts as `plugin-scan lua`.
/// Until this is called they run in this process, which is only for tests
/// of this crate: the engine's audio thread must not run Lua.
pub fn set_helper(exe: PathBuf, remote: Remote) {
    let _ = HELPER.set((exe, remote));
}

/// In a helper: make the device of the script it was started for.
pub fn serve_make(rate: f32, max_block: usize) -> Result<Instance> {
    let path = std::env::var_os(SCRIPT_ENV).context("no script was named for this helper")?;
    make(Path::new(&path), rate, max_block)
}

/// In a helper: say what each script named in `args` is, as one line of
/// JSON (a list of descriptions or reasons, in order). Returns the exit code.
pub fn scan_main(args: &[String]) -> i32 {
    let found: Vec<ScanAnswer> = args
        .iter()
        .map(|path| describe(Path::new(path)).map_err(|err| format!("{err:#}")))
        .collect();
    println!("{}", serde_json::to_string(&found).unwrap_or_default());
    0
}

/// Makes Lua devices in this process (see [`set_helper`]).
struct HereFactory {
    info: DeviceInfo,
    path: PathBuf,
}

impl DeviceFactory for HereFactory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance> {
        make(&self.path, sample_rate, max_block)
    }
}

fn factory(info: DeviceInfo, path: &Path) -> Rc<dyn DeviceFactory> {
    match HELPER.get() {
        Some((exe, remote)) => remote(
            info,
            vec![exe.to_string_lossy().into_owned(), "plugin-host".into()],
            vec![(SCRIPT_ENV.into(), path.to_string_lossy().into_owned())],
        ),
        None => Rc::new(HereFactory {
            info,
            path: path.to_path_buf(),
        }),
    }
}

/// Look into scripts: in a helper where there is one, so that a script
/// that crashes or never finishes loading costs nothing else.
fn describe_all(paths: &[PathBuf]) -> Vec<Result<Descriptor, ScanError>> {
    let Some((exe, _)) = HELPER.get() else {
        return paths
            .iter()
            .map(|p| describe(p).map_err(|err| ScanError::Script(format!("{err:#}"))))
            .collect();
    };
    let apart = || -> Result<Vec<ScanAnswer>, ScanError> {
        let mut child = std::process::Command::new(exe)
            .arg("plugin-scan")
            .arg("lua")
            .args(paths)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .spawn()?;
        let mut out = child.stdout.take().expect("the helper's output is piped");
        let reader = std::thread::spawn(move || {
            let mut text = String::new();
            let _ = out.read_to_string(&mut text);
            text
        });
        let started = Instant::now();
        let status = loop {
            if let Some(status) = child.try_wait()? {
                break status;
            }
            if started.elapsed() > SCAN_LIMIT {
                let _ = child.kill();
                let _ = child.wait();
                return Err(ScanError::Hung);
            }
            std::thread::sleep(Duration::from_millis(5));
        };
        let text = reader.join().unwrap_or_default();
        text.lines()
            .rev()
            .find_map(|line| serde_json::from_str(line).ok())
            .ok_or(ScanError::Failed(status))
    };
    match apart() {
        Ok(found) if found.len() == paths.len() => {
            found.into_iter().map(|answer| answer.map_err(ScanError::Script)).collect()
        }
        Ok(_) => vec![Err(ScanError::WrongAnswer); paths.len()],
        Err(err) => vec![Err(err); paths.len()],
    }
}

/// A file's modification time (in nanoseconds) and size: it is looked into
/// again when either changes.
fn stamp(path: &Path) -> Option<(u128, u64)> {
    let meta = std::fs::metadata(path).ok()?;
    let modified = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_nanos());
    Some((modified, meta.len()))
}

/// The kind a script's devices have: `lua:` and its file name without `.lua`.
pub fn kind_of(path: &Path) -> String {
    let stem = path.file_stem().unwrap_or_default().to_string_lossy();
    format!("lua:{stem}")
}

/// One script found in a directory.
struct Script {
    kind: String,
    /// Where it was found: a script in a directory of a higher rank wins
    /// over one of the same name in a lower one.
    rank: u8,
    stamp: (u128, u64),
    /// What it said it was when it last loaded.
    desc: Option<Descriptor>,
    /// Why it did not load, the last time it was looked into.
    error: Option<ScanError>,
}

/// Every directory looked in, and the scripts found there.
#[derive(Default)]
struct Library {
    dirs: Vec<(PathBuf, u8)>,
    scripts: BTreeMap<PathBuf, Script>,
}

thread_local! {
    static LIBRARY: RefCell<Library> = RefCell::default();
}

/// What a look at the scripts found.
#[derive(Debug, Default)]
pub struct Scanned {
    /// Kinds of scripts seen for the first time.
    pub added: Vec<String>,
    /// Kinds of scripts that changed and loaded: running devices of these
    /// kinds are behind their file.
    pub changed: Vec<String>,
    /// Scripts that did not load, as (kind, file, why). A device made from
    /// an earlier version is left as it is.
    pub errors: Vec<(String, PathBuf, String)>,
}

/// A script as listed by [`scripts`].
#[derive(Debug)]
pub struct Listed {
    pub kind: String,
    pub path: PathBuf,
    pub name: String,
    pub category: String,
    pub error: Option<String>,
    /// Whether its kind is this script's, and not another's of a higher rank.
    pub active: bool,
}

/// Look for scripts in `dir` too, from now on, and register what is found
/// there. `rank` says which wins where two directories have a script of the
/// same name: the higher.
pub fn add_dir(registry: &mut Registry, dir: &Path, rank: u8) -> Scanned {
    LIBRARY.with_borrow_mut(|lib| {
        match lib.dirs.iter_mut().find(|(d, _)| d == dir) {
            Some(known) => known.1 = rank,
            None => lib.dirs.push((dir.to_path_buf(), rank)),
        }
    });
    rescan(registry)
}

/// Look in `dir` no more. A kind one of its scripts made is made from now on
/// by a script of the same name in another directory, the highest ranked,
/// or by none; devices already made go on. Returns the kinds of its scripts.
pub fn remove_dir(registry: &mut Registry, dir: &Path) -> Vec<String> {
    LIBRARY.with_borrow_mut(|lib| {
        lib.dirs.retain(|(d, _)| d != dir);
        let mut gone = Vec::new();
        lib.scripts.retain(|path, script| {
            let here = path.parent() == Some(dir);
            if here {
                gone.push(script.kind.clone());
            }
            !here
        });
        for kind in &gone {
            let other = lib
                .scripts
                .iter()
                .filter(|(_, s)| &s.kind == kind && s.desc.is_some())
                .max_by_key(|(_, s)| s.rank);
            match other {
                Some((path, script)) => {
                    let desc = script.desc.as_ref().expect("filtered on desc");
                    registry.register(factory(info(path, script, desc), path));
                }
                None => {
                    registry.unregister(kind);
                }
            }
        }
        gone
    })
}

/// Look at every directory again: new scripts and changed ones are loaded
/// (in a helper) and registered.
pub fn rescan(registry: &mut Registry) -> Scanned {
    let mut scanned = Scanned::default();
    let dirs = LIBRARY.with_borrow(|lib| lib.dirs.clone());
    let mut present: BTreeMap<PathBuf, (u8, (u128, u64))> = BTreeMap::new();
    for (dir, rank) in &dirs {
        let Ok(entries) = std::fs::read_dir(dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().is_some_and(|e| e == "lua")
                && let Some(stamp) = stamp(&path)
            {
                present.insert(path, (*rank, stamp));
            }
        }
    }
    let todo: Vec<PathBuf> = LIBRARY.with_borrow_mut(|lib| {
        // Gone from the disk: devices already made go on as they are.
        lib.scripts.retain(|path, _| present.contains_key(path));
        present
            .iter()
            .filter(|(path, (rank, stamp))| match lib.scripts.get_mut(*path) {
                Some(known) => {
                    known.rank = *rank;
                    known.stamp != *stamp
                }
                None => true,
            })
            .map(|(path, _)| path.clone())
            .collect()
    });
    if todo.is_empty() {
        return scanned;
    }
    let found = describe_all(&todo);
    LIBRARY.with_borrow_mut(|lib| {
        for (path, result) in todo.into_iter().zip(found) {
            let (rank, stamp) = present[&path];
            let kind = kind_of(&path);
            let script = lib.scripts.entry(path.clone()).or_insert_with(|| Script {
                kind: kind.clone(),
                rank,
                stamp,
                desc: None,
                error: None,
            });
            script.stamp = stamp;
            match result {
                Ok(desc) => {
                    if script.desc.is_some() {
                        scanned.changed.push(kind);
                    } else {
                        scanned.added.push(kind);
                    }
                    script.desc = Some(desc);
                    script.error = None;
                }
                Err(why) => {
                    scanned.errors.push((kind, path, why.to_string()));
                    script.error = Some(why);
                }
            }
        }
        // Registered in order of rank, so that the highest is the one kept.
        let mut order: Vec<(&PathBuf, &Script)> = lib.scripts.iter().collect();
        order.sort_by_key(|(_, s)| s.rank);
        for (path, script) in order {
            if let Some(desc) = &script.desc {
                registry.register(factory(info(path, script, desc), path));
            }
        }
    });
    scanned
}

fn info(path: &Path, script: &Script, desc: &Descriptor) -> DeviceInfo {
    DeviceInfo {
        kind: script.kind.clone(),
        name: desc.name.clone().unwrap_or_else(|| {
            path.file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned()
        }),
        category: desc.category,
        format: DeviceFormat::Lua,
        vendor: desc.vendor.clone().unwrap_or_default(),
        params: desc.params.iter().map(device::Param::info).collect(),
        ..Default::default()
    }
}

/// Every script found, by file.
pub fn scripts() -> Vec<Listed> {
    LIBRARY.with_borrow(|lib| {
        let winner = |kind: &str| {
            lib.scripts
                .iter()
                .filter(|(_, s)| s.kind == kind && s.desc.is_some())
                .max_by_key(|(_, s)| s.rank)
                .map(|(p, _)| p.clone())
        };
        lib.scripts
            .iter()
            .map(|(path, s)| Listed {
                kind: s.kind.clone(),
                path: path.clone(),
                name: s
                    .desc
                    .as_ref()
                    .and_then(|d| d.name.clone())
                    .unwrap_or_else(|| s.kind[4..].to_string()),
                category: s.desc.as_ref().map(|d| d.category.to_string()).unwrap_or_default(),
                error: s.error.as_ref().map(ToString::to_string),
                active: winner(&s.kind).as_ref() == Some(path),
            })
            .collect()
    })
}
