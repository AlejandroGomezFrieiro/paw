//! Plugins in processes of their own.
//!
//! A plugin is other people's code. Loaded into this process, one that
//! crashes takes the session with it, and one that hangs freezes it. So each
//! plugin instance runs in a helper process (this same program, started as
//! `plugin-host`), and the session holds a stand-in for it:
//!
//! ```text
//!  the DAW                                   plugin-host (one per instance)
//!   audio thread ── shared memory, futex ──▶ audio thread: the plugin's process()
//!   main thread  ── socket ────────────────▶ main thread: parameters, state, editor
//! ```
//!
//! Audio crosses in a block of shared memory. The DAW's audio thread writes
//! a block's input there, wakes the helper and waits for the answer, but
//! never longer than about a block lasts: a plugin that is late costs its
//! own track a block of sound, not everyone a dropout, and one that has died
//! costs nothing more. An instrument that is late or gone is silent; an
//! effect is passed through. The events of blocks a late helper did not
//! take are not lost: they reach it at the start of the next it takes.
//!
//! Everything else crosses a socket, each request with a time limit, so a
//! plugin that hangs while it is created, or saving its state, is reported
//! and ended instead of freezing the program.
//!
//! The helper finds the plugin the way the DAW does (`register`, from the
//! same cache and the same folders), creates it, and opens its editor in a window of its own, so
//! plugin windows work exactly as they do in-process.
//!
//! Tests ask a running plugin through `paw.api.device_call`:
//! `sandbox.pid` gives its helper's process, `sandbox.late` the blocks it
//! did not answer in time, and `sandbox.hang` and `sandbox.deadline` make
//! it and the plugins of its kind made after it stop answering, and a
//! render give up on them soon ([`KindTest`]). A device that is still
//! loading takes `sandbox.hold`, `sandbox.release`, `sandbox.hang` and
//! `sandbox.deadline` in the session, which passes the last two to
//! [`DeviceFactory::start`] as a `StartTest`.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::atomic::AtomicBool;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use paw_engine::Registry;
use paw_engine::device::{DeviceFactory, DeviceInfo};

mod controller;
mod device;
mod factory;
mod serve;
mod shm;
mod wire;

use factory::RemoteFactory;
pub use serve::{serve, serve_with};


/// How the helper is started: this program and its first arguments.
static HOST: OnceLock<Vec<String>> = OnceLock::new();
/// The plugin cache the helper reads, the DAW's own.
static CACHE: Mutex<Option<PathBuf>> = Mutex::new(None);

/// Events a block may carry each way.
const EVENTS: usize = 1024;
/// Parameter moves a block may carry to the plugin.
const PARAMS: usize = 256;
/// Parameter changes the plugin reports that may wait to be read.
const CHANGES: usize = 1024;
const MAGIC: u32 = 0x4441_5750;
/// The longest reason a helper can give for stopping.
const REASON: usize = 1024;
/// Bytes of state lanes' messages a block may carry to the plugin.
const MESSAGES: usize = 16384;
/// The call that asks the helper's controller to prepare a message
/// ([`Controller::prepare`]): its data is the method, a zero byte, the
/// request's own data.
const PREPARE: &str = "sandbox.prepare";

/// How long a plugin may take over each kind of request before it is
/// taken to have hung.
const CREATE_LIMIT: Duration = Duration::from_secs(45);
const STATE_LIMIT: Duration = Duration::from_secs(30);
const QUICK_LIMIT: Duration = Duration::from_secs(10);
/// A plugin that answers no block for this long while it is asked for them
/// is taken to have hung: it is ended and reported, and can be restarted.
const STALL_LIMIT: Duration = Duration::from_secs(2);
/// The longest a render waits for one block. A plugin that takes longer is
/// treated as stopped for the rest of the render, which goes on without it.
const OFFLINE_LIMIT: Duration = Duration::from_secs(20);

/// For tests, in a helper: its audio thread stops answering blocks (it
/// sleeps instead), until `sandbox.hang 0`. Set by `sandbox.hang`, or at
/// the helper's start when its kind hangs ([`KindTest`]).
static TEST_HANG: AtomicBool = AtomicBool::new(false);

/// For tests, in the DAW: what `sandbox.hang` and `sandbox.deadline` on a
/// running plugin asked of the plugins of its kind that are made from now
/// on, a render's own among them. A plugin of another kind never meets it.
#[derive(Clone, Copy, Debug, Default)]
struct KindTest {
    /// Their helpers stop answering blocks, as the plugin's did.
    hang: bool,
    /// A render waits this long for one of their blocks, in place of
    /// [`OFFLINE_LIMIT`].
    deadline: Option<Duration>,
}

/// The [`KindTest`] of each kind that a test changed, by kind.
static KIND_TESTS: Mutex<BTreeMap<String, KindTest>> = Mutex::new(BTreeMap::new());

fn kind_test(kind: &str) -> KindTest {
    KIND_TESTS
        .lock()
        .unwrap()
        .get(kind)
        .copied()
        .unwrap_or_default()
}

/// Change what the tests ask of the plugins of `kind`; a kind asked for
/// nothing more is forgotten.
fn set_kind_test(kind: &str, change: impl FnOnce(&mut KindTest)) {
    let mut tests = KIND_TESTS.lock().unwrap();
    let test = tests.entry(kind.to_string()).or_default();
    change(test);
    if !test.hang && test.deadline.is_none() {
        tests.remove(kind);
    }
}

/// Say how to start the helper: the program and the arguments that put it
/// in `plugin-host` mode. Until this is called plugins are hosted in-process,
/// which is what tests of the hosting code itself want.
pub fn set_host_command(argv: Vec<String>, cache: Option<&Path>) {
    let _ = HOST.set(argv);
    *CACHE.lock().unwrap() = cache.map(Path::to_path_buf);
}

/// Whether plugins get processes of their own: the helper is known, and
/// `PAW_PLUGIN_SANDBOX=0` has not turned it off.
pub fn enabled() -> bool {
    HOST.get().is_some() && std::env::var("PAW_PLUGIN_SANDBOX").as_deref() != Ok("0")
}

pub(crate) fn host_command() -> Option<&'static Vec<String>> {
    if enabled() { HOST.get() } else { None }
}

/// Replace every plugin's factory with one that makes it in a helper.
/// Built-in devices are this program's own code and stay where they are.
/// Each helper gets the folders added in `dirs` now, the folders where its
/// plugin was found.
pub fn wrap(registry: &mut Registry, dirs: &crate::PluginDirs) {
    if !enabled() {
        return;
    }
    let plugins: Vec<DeviceInfo> = registry
        .iter()
        .map(|factory| factory.info().clone())
        .filter(|info| info.format.is_plugin())
        .collect();
    let added_dirs = dirs.added_for_helper();
    for info in plugins {
        registry.register(Rc::new(RemoteFactory {
            info,
            argv: None,
            env: Vec::new(),
            added_dirs: added_dirs.clone(),
        }));
    }
}

/// A factory that makes each device in a helper started with `argv` (this
/// program and the arguments that put it in `plugin-host` mode), whether or
/// not plugins get helpers: for devices that must never run in this
/// process. `env` is added to the helper's environment.
pub fn remote(
    info: DeviceInfo,
    argv: Vec<String>,
    env: Vec<(String, String)>,
) -> Rc<dyn DeviceFactory> {
    Rc::new(RemoteFactory {
        info,
        argv: Some(argv),
        env,
        added_dirs: None,
    })
}

