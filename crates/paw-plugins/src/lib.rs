//! Hosts CLAP, LV2 and VST3 plugins as engine devices.
//!
//! Each format module scans for installed plugins and registers a
//! [`DeviceFactory`](paw_engine::DeviceFactory) for every one it finds. A
//! created plugin is split in two, like any device with a controller: the part
//! that processes audio moves to the audio thread, and a controller stays on
//! the main thread for parameters and state.
//!
//! Plugins are other people's code. A program that says how to start a
//! helper ([`sandbox::set_host_command`]) gets each plugin in a process of
//! its own, where one that crashes or hangs is lost alone, and plugin files
//! are looked into in a process of their own too. Without that, plugins are
//! loaded into this process, and one that crashes takes the program with it.

#![warn(clippy::undocumented_unsafe_blocks)]

pub mod attach;
pub mod clap;
mod echo;
pub mod libs;
pub mod lv2;
mod lv2_patch;
pub mod presets;
pub mod sandbox;
pub mod vst3;
mod window;

pub use window::repair_display_env;

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::{Mutex, OnceLock};
use std::thread::ThreadId;
use std::time::UNIX_EPOCH;

use paw_engine::{
    Category, DeviceFactory, DeviceFormat, DeviceInfo, Event, EventKind, Registry,
};
use serde::{Deserialize, Serialize};

static MAIN_THREAD: OnceLock<ThreadId> = OnceLock::new();

/// Whether the caller is on the thread that called [`register`].
pub(crate) fn is_main_thread() -> bool {
    MAIN_THREAD.get() == Some(&std::thread::current().id())
}

/// Find installed plugins and add a device kind for each: `clap:<id>`,
/// `lv2:<uri>` and `vst3:<name>`. Call from the main thread. Returns notes
/// about plugins that were found but could not be used.
///
/// Listing what a CLAP or VST3 file contains means loading it, which for some
/// plugins is slow and noisy (bridged Windows plugins start Wine). The result
/// is remembered in `cache_file`, so a file is only loaded again when it
/// changes or when a plugin from it is actually used.
pub fn register(registry: &mut Registry, cache_file: Option<&Path>) -> Vec<String> {
    MAIN_THREAD.get_or_init(|| std::thread::current().id());
    let mut cache = Cache::load(cache_file);
    let mut notes = Vec::new();
    scan::<clap::Clap>(registry, &mut cache, &mut notes);
    lv2::scan(registry, &mut cache, &mut notes);
    scan::<vst3::Vst3>(registry, &mut cache, &mut notes);
    cache.save(cache_file);
    if !cache.skipped.is_empty() {
        let n = cache.skipped.len();
        notes.insert(
            0,
            format!(
                "skipped {n} plugin file{} that failed when looked into before ({}): `:plugins.rescan` tries again",
                if n == 1 { "" } else { "s" },
                cache.skipped.join(", ")
            ),
        );
    }
    notes
}

/// Look into plugin files again, as if they had changed: every one, or
/// (with `name`) those whose file name or plugin names contain it. Their
/// device kinds are registered again, in helper processes where those are
/// used. Returns the notes [`register`] does.
pub fn rescan(
    registry: &mut Registry,
    cache_file: Option<&Path>,
    name: Option<&str>,
) -> Vec<String> {
    let mut cache = Cache::load(cache_file);
    match name {
        None => {
            cache.files.clear();
            cache.lv2 = None;
        }
        Some(name) => {
            let name = name.to_lowercase();
            cache.files.retain(|path, file| {
                let named = path.to_string_lossy().to_lowercase().contains(&name)
                    || file.plugins.as_ref().is_ok_and(|found| {
                        found.iter().any(|p| p.name.to_lowercase().contains(&name))
                    });
                !named
            });
        }
    }
    cache.write();
    let notes = register(registry, cache_file);
    sandbox::wrap(registry);
    notes
}

/// Directories added for this session ([`add_dir`]), looked in for CLAP
/// and VST3 plugins besides the usual ones.
static ADDED_DIRS: Mutex<Vec<PathBuf>> = Mutex::new(Vec::new());

/// How the directories added are handed to a plugin's helper, which has to
/// find the plugin where this process did.
pub(crate) const ADDED_DIRS_ENV: &str = "PAW_PLUGIN_DIRS";

/// Look in `dir` for CLAP and VST3 plugins from now on, as well as where
/// plugins are usually installed (an extension that ships its own plugins
/// adds the directory they are built into), and register those in it now.
/// Returns the device kinds found there, and notes on files that could not
/// be used. The directory is kept until the program ends; later rescans
/// look in it too.
pub fn add_dir(
    registry: &mut Registry,
    cache_file: Option<&Path>,
    dir: &Path,
) -> (Vec<String>, Vec<String>) {
    MAIN_THREAD.get_or_init(|| std::thread::current().id());
    {
        let mut dirs = ADDED_DIRS.lock().unwrap();
        if !dirs.iter().any(|d| d == dir) {
            dirs.push(dir.to_path_buf());
        }
    }
    // Only the new directory is looked into; the cache keeps what it knew
    // of the rest, which is why it is not saved (and pruned) here.
    let mut cache = Cache::load(cache_file);
    let mut found = Registry::default();
    let mut notes = Vec::new();
    let dirs = [dir.to_path_buf()];
    scan_in::<clap::Clap>(&mut found, &mut cache, &mut notes, &dirs);
    scan_in::<vst3::Vst3>(&mut found, &mut cache, &mut notes, &dirs);
    sandbox::wrap(&mut found);
    let mut kinds = Vec::new();
    for factory in found.iter() {
        kinds.push(factory.info().kind.clone());
        registry.register(factory.clone());
    }
    (kinds, notes)
}

/// Look in `dir` no more: an extension that added it was taken away.
pub fn remove_dir(dir: &Path) {
    ADDED_DIRS.lock().unwrap().retain(|d| d != dir);
}

/// The directories added so far, as [`ADDED_DIRS_ENV`] holds them.
pub(crate) fn added_dirs_env() -> Option<std::ffi::OsString> {
    let dirs = ADDED_DIRS.lock().unwrap();
    if dirs.is_empty() {
        return None;
    }
    std::env::join_paths(dirs.iter()).ok()
}

/// Take the directories a helper was handed ([`ADDED_DIRS_ENV`]).
pub(crate) fn adopt_added_dirs() {
    if let Some(paths) = std::env::var_os(ADDED_DIRS_ENV) {
        ADDED_DIRS
            .lock()
            .unwrap()
            .extend(std::env::split_paths(&paths));
    }
}

/// One plugin inside a plugin file, as remembered between runs.
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct Found {
    /// What the format uses to create the plugin: a CLAP id, a VST3 class id.
    pub id: String,
    pub name: String,
    pub vendor: String,
    pub instrument: bool,
    /// The version the plugin gives; empty in a cache from before it was kept.
    #[serde(default)]
    pub version: String,
    /// Its features (CLAP); empty in a cache from before they were kept.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub features: Vec<String>,
}

impl Found {
    /// The device that this plugin is registered as, under `kind`.
    pub fn device_info(self, kind: String, format: DeviceFormat) -> DeviceInfo {
        DeviceInfo {
            kind,
            name: self.name,
            category: if self.instrument {
                Category::Instrument
            } else {
                Category::Effect
            },
            format,
            vendor: self.vendor,
            id: self.id,
            version: self.version,
            params: Vec::new(),
            features: self.features,
        }
    }
}

/// A plugin format whose plugins are found file by file (CLAP and VST3; LV2
/// is read as one world by lilv, see [`lv2::scan`]): what [`scan_in`] needs to
/// know of it.
pub(crate) trait PluginFormat {
    /// The format's name as [`list_apart`] takes it, which is also the
    /// extension of its files.
    const NAME: &'static str;
    const FORMAT: DeviceFormat;
    /// The environment variable that replaces the usual places to look.
    const ENV: &'static str;
    /// The same plugin found in two places is registered once (the first).
    const ONE_PER_ID: bool;
    /// The file in `bundle` that the cache is keyed by, or `None` to pass
    /// the bundle over.
    fn library(bundle: &Path) -> Option<PathBuf>;
    /// Load `bundle` and list the plugins in it, in this process.
    fn list(bundle: &Path) -> anyhow::Result<Vec<Found>>;
    /// The device kind of a plugin, unique in `registry`.
    fn kind(found: &Found, registry: &Registry) -> String;
    /// The factory of a plugin found in `bundle`, or `None` when its id is
    /// not one the format can use.
    fn factory(info: DeviceInfo, bundle: &Path) -> Option<Rc<dyn DeviceFactory>>;
}

/// Register the plugins of format `F` found where that format is installed.
pub(crate) fn scan<F: PluginFormat>(
    registry: &mut Registry,
    cache: &mut Cache,
    notes: &mut Vec<String>,
) {
    scan_in::<F>(registry, cache, notes, &search_dirs(F::ENV, F::NAME));
}

/// Register the plugins of format `F` in the files under `dirs`.
pub(crate) fn scan_in<F: PluginFormat>(
    registry: &mut Registry,
    cache: &mut Cache,
    notes: &mut Vec<String>,
    dirs: &[PathBuf],
) {
    let mut seen = std::collections::HashSet::new();
    for bundle in find_bundles(dirs, F::NAME) {
        let Some(library) = F::library(&bundle) else {
            continue;
        };
        match cache.plugins(&library, || {
            list_apart(F::NAME, &bundle, || F::list(&bundle))
        }) {
            Ok(found) => {
                for plugin in found {
                    if F::ONE_PER_ID && !seen.insert(plugin.id.clone()) {
                        continue;
                    }
                    let kind = F::kind(&plugin, registry);
                    let info = plugin.device_info(kind, F::FORMAT);
                    if let Some(factory) = F::factory(info, &bundle) {
                        registry.register(factory);
                    }
                }
            }
            Err(err) => notes.push(format!("{}: {err}", bundle.display())),
        }
    }
}

#[derive(Serialize, Deserialize)]
struct CachedFile {
    modified: u64,
    size: u64,
    /// The plugins in the file, or why it could not be read.
    plugins: Result<Vec<Found>, String>,
}

/// What each plugin file contained the last time it was loaded.
/// The LV2 plugins found last time, and what the bundles they came from
/// looked like then. LV2 is not scanned per file: lilv reads every bundle's
/// metadata at once, which with large collections takes over a second.
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct Lv2Cache {
    /// Every bundle with the latest modification time of it and its files.
    pub bundles: Vec<(PathBuf, u64)>,
    pub plugins: Vec<Found>,
    /// Plugins left out because they need host features this host lacks.
    pub skipped: usize,
}

#[derive(Default, Serialize, Deserialize)]
pub(crate) struct Cache {
    files: HashMap<PathBuf, CachedFile>,
    #[serde(default)]
    pub lv2: Option<Lv2Cache>,
    #[serde(skip)]
    changed: bool,
    #[serde(skip)]
    seen: Vec<PathBuf>,
    /// Where the cache is kept, to write it as soon as something is learnt.
    #[serde(skip)]
    file: Option<PathBuf>,
    /// The file being looked into right now, written before it is: if the
    /// program itself is ended meanwhile, the next start knows which it was.
    #[serde(default)]
    scanning: Option<PathBuf>,
    /// Files passed over because they failed before, by name.
    #[serde(skip)]
    skipped: Vec<String>,
}

/// Why a file is passed over that was being looked into when the program ended.
const ENDED_WHILE_SCANNING: &str = "the program ended while this was looked into";

impl Cache {
    fn load(file: Option<&Path>) -> Self {
        let mut cache: Self = file
            .and_then(|f| std::fs::read(f).ok())
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        cache.file = file.map(Path::to_path_buf);
        // Ended (killed, or the machine went down) in the middle of a file:
        // that file is counted as failed, and not looked into again unasked.
        if let Some(path) = cache.scanning.take()
            && !cache.files.contains_key(&path)
        {
            let (modified, size) = stamp(&path);
            cache.files.insert(
                path,
                CachedFile {
                    modified,
                    size,
                    plugins: Err(ENDED_WHILE_SCANNING.into()),
                },
            );
            cache.changed = true;
            cache.write();
        }
        cache
    }

    /// Write the cache out as it is now.
    fn write(&self) {
        let Some(file) = &self.file else { return };
        if let Some(dir) = file.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(text) = serde_json::to_vec_pretty(self) {
            // Whole or not at all: a half-written cache would be thrown away.
            let tmp = file.with_extension("json.tmp");
            if std::fs::write(&tmp, text).is_ok() {
                let _ = std::fs::rename(&tmp, file);
            }
        }
    }

    fn save(&mut self, file: Option<&Path>) {
        // Forget files that are no longer installed.
        let before = self.files.len();
        let seen = std::mem::take(&mut self.seen);
        self.files.retain(|path, _| seen.contains(path));
        if file.is_none() || (!self.changed && before == self.files.len()) {
            return;
        }
        self.write();
    }

    /// Note that the cache must be written out.
    pub fn mark_changed(&mut self) {
        self.changed = true;
    }

    /// The plugins in `path`, calling `scan` only if the file is new or has
    /// changed since it was last scanned.
    pub fn plugins(
        &mut self,
        path: &Path,
        scan: impl FnOnce() -> anyhow::Result<Vec<Found>>,
    ) -> Result<Vec<Found>, String> {
        // Key by the real file: plugin directories are often full of links.
        let real = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
        let (modified, size) = stamp(&real);
        self.seen.push(real.clone());
        if let Some(known) = self.files.get(&real)
            && (known.modified, known.size) == (modified, size)
        {
            if known.plugins.is_err() {
                let name = real.file_name().unwrap_or_default().to_string_lossy();
                self.skipped.push(name.into_owned());
            }
            return known.plugins.clone();
        }
        self.scanning = Some(real.clone());
        self.write();
        let plugins = scan().map_err(|err| format!("{err:#}"));
        self.scanning = None;
        self.changed = true;
        self.files.insert(
            real,
            CachedFile {
                modified,
                size,
                plugins: plugins.clone(),
            },
        );
        // Kept at once: looking into a file can take long, and what was
        // learnt should outlast whatever happens with the next one.
        self.write();
        plugins
    }
}

/// How long a plugin file may take to say what is in it. Bridged Windows
/// plugins start Wine first, which is slow the first time.
const LIST_LIMIT: std::time::Duration = std::time::Duration::from_secs(120);

/// What is in a plugin file, found out in a process of its own where there
/// is a helper to ask: a file that crashes or hangs while it is looked into
/// is noted as that, and nothing else is lost. `here` does it in this
/// process when there is no helper.
pub(crate) fn list_apart(
    format: &str,
    path: &Path,
    here: impl FnOnce() -> anyhow::Result<Vec<Found>>,
) -> anyhow::Result<Vec<Found>> {
    use std::io::Read;
    use std::os::unix::process::ExitStatusExt;
    let Some(argv) = sandbox::host_command() else {
        return here();
    };
    // The helper's command ends in `plugin-host`; its neighbour lists a file.
    let mut child = std::process::Command::new(&argv[0])
        .arg("plugin-scan")
        .arg(format)
        .arg(path)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()?;
    let mut out = child.stdout.take().expect("piped");
    let reader = std::thread::spawn(move || {
        let mut text = String::new();
        let _ = out.read_to_string(&mut text);
        text
    });
    let started = std::time::Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if started.elapsed() > LIST_LIMIT {
            let _ = child.kill();
            let _ = child.wait();
            anyhow::bail!(
                "it did not answer for {} seconds while it was looked into",
                LIST_LIMIT.as_secs()
            );
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    };
    let text = reader.join().unwrap_or_default();
    // The answer is the last line: plugins print what they like before it.
    let answer = text
        .lines()
        .rev()
        .find_map(|line| serde_json::from_str::<Result<Vec<Found>, String>>(line).ok());
    match answer {
        Some(Ok(found)) => Ok(found),
        Some(Err(why)) => anyhow::bail!("{why}"),
        None => match status.signal() {
            Some(signal) => anyhow::bail!("it crashed while it was looked into (signal {signal})"),
            None => anyhow::bail!("looking into it failed ({status})"),
        },
    }
}

/// Run as the helper that says what is in one plugin file: `args` are the
/// format and the file. The answer is the last line it prints.
pub fn scan_main(args: &[String]) -> i32 {
    MAIN_THREAD.get_or_init(|| std::thread::current().id());
    let found: Result<Vec<Found>, String> = match args {
        [format, path] if format == "vst3" => vst3::list_file(Path::new(path)),
        [format, path] if format == "clap" => clap::list_file(Path::new(path)),
        _ => Err(anyhow::anyhow!("usage: plugin-scan <vst3|clap> <file>")),
    }
    .map_err(|err| format!("{err:#}"));
    println!("{}", serde_json::to_string(&found).unwrap_or_default());
    0
}

/// A file's modification time (seconds since the epoch) and size, or zeros.
fn stamp(path: &Path) -> (u64, u64) {
    let meta = std::fs::metadata(path).ok();
    let modified = meta
        .as_ref()
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_secs());
    (modified, meta.map_or(0, |m| m.len()))
}

/// Seconds since the epoch at which a file was last modified, or 0.
pub(crate) fn mtime(path: &Path) -> u64 {
    std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_secs())
}

/// Directories to search for one plugin format: the format's environment
/// variable if set, else the usual per-user and system locations; and those
/// added by [`add_dir`].
pub(crate) fn search_dirs(env: &str, name: &str) -> Vec<PathBuf> {
    let mut dirs = usual_dirs(env, name);
    dirs.extend(ADDED_DIRS.lock().unwrap().iter().cloned());
    dirs
}

fn usual_dirs(env: &str, name: &str) -> Vec<PathBuf> {
    if let Some(paths) = std::env::var_os(env) {
        return std::env::split_paths(&paths).collect();
    }
    let mut dirs = Vec::new();
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        dirs.push(home.join(format!(".{name}")));
        dirs.push(home.join(format!(".nix-profile/lib/{name}")));
    }
    if let Some(user) = std::env::var_os("USER") {
        dirs.push(
            Path::new("/etc/profiles/per-user")
                .join(user)
                .join("lib")
                .join(name),
        );
    }
    for prefix in ["/run/current-system/sw/lib", "/usr/local/lib", "/usr/lib"] {
        dirs.push(Path::new(prefix).join(name));
    }
    dirs
}

/// Every entry under `dirs` whose name ends in `extension`, searching
/// subdirectories but not inside matches.
pub(crate) fn find_bundles(dirs: &[PathBuf], extension: &str) -> Vec<PathBuf> {
    fn walk(dir: &Path, extension: &str, depth: u32, out: &mut Vec<PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().is_some_and(|e| e == extension) {
                out.push(path);
            } else if depth < 4 && path.is_dir() {
                walk(&path, extension, depth + 1, out);
            }
        }
    }
    let mut out = Vec::new();
    for dir in dirs {
        walk(dir, extension, 0, &mut out);
    }
    out.sort();
    out.dedup();
    out
}

/// Tracks which notes are sounding, so that "all notes off" can be sent as
/// the individual note-offs every plugin understands.
pub(crate) struct HeldNotes {
    /// The channels each key sounds on, one bit each.
    held: [u16; 128],
}

impl HeldNotes {
    pub fn new() -> Self {
        Self { held: [0; 128] }
    }

    /// Feed the block's events through, calling `emit` for each note event
    /// with "all notes off" expanded.
    pub fn expand(&mut self, events: &[Event], mut emit: impl FnMut(u32, EventKind)) {
        for event in events {
            match event.kind {
                EventKind::NoteOn { key, ch, .. } => {
                    self.held[(key & 127) as usize] |= 1 << (ch & 15);
                    emit(event.frame, event.kind);
                }
                EventKind::NoteOff { key, ch } => {
                    self.held[(key & 127) as usize] &= !(1 << (ch & 15));
                    emit(event.frame, event.kind);
                }
                EventKind::Control { .. }
                | EventKind::NoteControl { .. }
                | EventKind::Program { .. } => emit(event.frame, event.kind),
                EventKind::AllNotesOff => {
                    for key in 0..128u8 {
                        let channels = std::mem::take(&mut self.held[key as usize]);
                        for ch in (0..16u8).filter(|ch| channels & 1 << ch != 0) {
                            emit(event.frame, EventKind::NoteOff { key, ch });
                        }
                    }
                }
            }
        }
    }
}

/// Put a block of side-chain into a plugin's side-chain channels (a mono
/// one gets both sides at half level each), or silence them once when it is
/// taken away. `held` says whether they hold one now; the answer is whether
/// they do afterwards.
pub(crate) fn put_key<C: AsMut<[f32]>>(
    channels: &mut [C],
    key: Option<[&[f32]; 2]>,
    held: bool,
    n: usize,
) -> bool {
    match (key, channels) {
        (_, []) => false,
        (Some([l, r]), [mono]) => {
            for (m, (l, r)) in mono.as_mut()[..n].iter_mut().zip(l.iter().zip(r)) {
                *m = (l + r) * 0.5;
            }
            true
        }
        (Some([l, r]), [left, right, ..]) => {
            left.as_mut()[..n].copy_from_slice(&l[..n]);
            right.as_mut()[..n].copy_from_slice(&r[..n]);
            true
        }
        (None, channels) => {
            if held {
                for ch in channels {
                    ch.as_mut().fill(0.0);
                }
            }
            false
        }
    }
}

/// One stereo pair of a plugin's outputs: the port (or bus) it is on, the
/// channels of its two sides there, and its name.
pub(crate) struct OutPair {
    pub port: usize,
    pub left: usize,
    pub right: usize,
    pub name: String,
}

/// A plugin's outputs as stereo pairs, the main one first: each port's
/// channels two by two (a lone one as both sides), named after the port,
/// with the channels' numbers where a port has more than two. Ports are
/// given as their channel count and name. At most [`MAX_PAIRS`].
///
/// [`MAX_PAIRS`]: paw_engine::MAX_PAIRS
pub(crate) fn out_pairs(ports: &[(usize, String)]) -> Vec<OutPair> {
    let mut pairs = Vec::new();
    for (port, (channels, name)) in ports.iter().enumerate() {
        for left in (0..*channels).step_by(2) {
            let right = (left + 1).min(channels - 1);
            let name = match (name.trim(), *channels > 2) {
                ("", _) => format!("Out {}", pairs.len() + 1),
                (name, true) => format!("{name} {}-{}", left + 1, right + 1),
                (name, false) => name.to_string(),
            };
            pairs.push(OutPair {
                port,
                left,
                right,
                name,
            });
        }
    }
    pairs.truncate(paw_engine::MAX_PAIRS);
    pairs
}

/// The names of a plugin's output pairs, for [`paw_engine::Ports::outputs`]:
/// none for a plugin with one.
pub(crate) fn pair_names(pairs: &[OutPair]) -> Vec<String> {
    if pairs.len() < 2 {
        return Vec::new();
    }
    pairs.iter().map(|p| p.name.clone()).collect()
}

/// Copy a plugin's further output pairs (all but the first) into those the
/// host asks for.
pub(crate) fn write_pairs(
    pairs: &[OutPair],
    channels: &[Vec<Vec<f32>>],
    outputs: &mut [Option<[Vec<f32>; 2]>],
    n: usize,
) {
    for (pair, out) in pairs.iter().skip(1).zip(outputs.iter_mut()) {
        let (Some(port), Some([l, r])) = (channels.get(pair.port), out) else {
            continue;
        };
        if let (Some(left), Some(right)) = (port.get(pair.left), port.get(pair.right)) {
            l[..n].copy_from_slice(&left[..n]);
            r[..n].copy_from_slice(&right[..n]);
        }
    }
}

/// Copy a plugin's stereo, mono or wider output into the track's two channels.
/// Instruments add to what is on the track; effects replace it.
pub(crate) fn write_output(left: &mut [f32], right: &mut [f32], out: &[&[f32]], add: bool) {
    let (Some(l), r) = (out.first(), out.get(1).or(out.first())) else {
        return;
    };
    let r = r.unwrap();
    for (i, (dl, dr)) in left.iter_mut().zip(right.iter_mut()).enumerate() {
        if add {
            *dl += l[i];
            *dr += r[i];
        } else {
            *dl = l[i];
            *dr = r[i];
        }
    }
}
