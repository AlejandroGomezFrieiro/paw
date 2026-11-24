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

pub mod attach;
pub mod clap;
mod dirs;
mod echo;
pub mod libs;
pub mod lv2;
mod lv2_patch;
pub mod presets;
pub mod sandbox;
pub mod vst3;
mod window;

pub use dirs::PluginDirs;
pub use window::repair_display_env;

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::OnceLock;
use std::thread::ThreadId;
use std::time::UNIX_EPOCH;

use paw_engine::{Category, DeviceFactory, DeviceFormat, DeviceInfo, Event, Registry};
use paw_types::EventKind;
use serde::{Deserialize, Serialize};

static MAIN_THREAD: OnceLock<ThreadId> = OnceLock::new();

/// Whether the caller is on the thread that called [`register`].
pub(crate) fn is_main_thread() -> bool {
    MAIN_THREAD.get() == Some(&std::thread::current().id())
}

/// In a debug build, panic when a call that only the main thread may make
/// (lilv's world, a VST3 module's objects) comes from another thread. Before
/// [`register`] has named the main thread (a sandboxed plugin's process, a
/// test), any thread passes.
#[inline]
pub(crate) fn debug_assert_main_thread() {
    debug_assert!(
        MAIN_THREAD
            .get()
            .is_none_or(|main| *main == std::thread::current().id()),
        "a call that only the main thread may make came from another thread"
    );
}

/// Find installed plugins and add a device kind for each: `clap:<id>`,
/// `lv2:<uri>` and `vst3:<name>`. Call from the main thread. Returns notes
/// about plugins that were found but could not be used.
///
/// Listing what a CLAP or VST3 file contains means loading it, which for some
/// plugins is slow and noisy (bridged Windows plugins start Wine). The result
/// is remembered in `cache_file`, so a file is only loaded again when it
/// changes or when a plugin from it is actually used. `dirs` says where
/// to look.
pub fn register(
    registry: &mut Registry,
    cache_file: Option<&Path>,
    dirs: &PluginDirs,
) -> Vec<String> {
    MAIN_THREAD.get_or_init(|| std::thread::current().id());
    let mut cache = Cache::load(cache_file);
    let mut notes = Vec::new();
    scan::<clap::Clap>(registry, &mut cache, &mut notes, dirs);
    lv2::scan(registry, &mut cache, &mut notes, dirs);
    scan::<vst3::Vst3>(registry, &mut cache, &mut notes, dirs);
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
/// (with `name`) those whose file name or plugin names contain it. All
/// plugins are then registered again, in helper processes where those are
/// used, with the kinds that a new start gives them: a plugin that is not
/// found again has no kind any more. Returns the notes [`register`] does.
pub fn rescan(
    registry: &mut Registry,
    cache_file: Option<&Path>,
    name: Option<&str>,
    dirs: &PluginDirs,
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
    // The plugins are registered again from nothing, as a helper process
    // registers them. A kind of the last scan that stays would take the
    // name of a VST3 plugin, and the plugin would come back as
    // `vst3:<name> (2)`: a kind that no helper knows.
    registry.unregister_where(|info| info.format.is_plugin());
    let notes = register(registry, cache_file, dirs);
    sandbox::wrap(registry, dirs);
    notes
}

/// Look in `dir` for CLAP and VST3 plugins from now on, as well as where
/// plugins are usually installed (an extension that ships its own plugins
/// adds the directory they are built into), and register those in it now.
/// Returns the device kinds found there, and notes on files that could not
/// be used. `dirs` keeps the directory, and later rescans with it look in
/// it too, until [`PluginDirs::remove`].
pub fn add_dir(
    registry: &mut Registry,
    cache_file: Option<&Path>,
    dirs: &mut PluginDirs,
    dir: &Path,
) -> (Vec<String>, Vec<String>) {
    MAIN_THREAD.get_or_init(|| std::thread::current().id());
    dirs.add(dir);
    // Only the new directory is looked into; the cache keeps what it knew
    // of the rest, which is why it is not saved (and pruned) here.
    let mut cache = Cache::load(cache_file);
    // The scan starts from the plugins that are registered already, as a
    // helper scans the added folder after the others: a VST3 plugin that
    // is known already is not registered again, and a new one with the
    // name of another gets the next free kind.
    let mut found = Registry::default();
    for factory in registry.iter().filter(|f| f.info().format.is_plugin()) {
        found.register(factory.clone());
    }
    let known = found.clone();
    let mut notes = Vec::new();
    let only = [dir.to_path_buf()];
    scan_in::<clap::Clap>(&mut found, &mut cache, &mut notes, dirs, &only);
    scan_in::<vst3::Vst3>(&mut found, &mut cache, &mut notes, dirs, &only);
    // Only the factories that the scan made are wrapped and registered.
    let mut added = Registry::default();
    for factory in found.iter() {
        let made_now = known
            .get(&factory.info().kind)
            .is_none_or(|was| !Rc::ptr_eq(was, factory));
        if made_now {
            added.register(factory.clone());
        }
    }
    sandbox::wrap(&mut added, dirs);
    let mut kinds = Vec::new();
    for factory in added.iter() {
        kinds.push(factory.info().kind.clone());
        registry.register(factory.clone());
    }
    (kinds, notes)
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
    pub(crate) fn device_info(self, kind: String, format: DeviceFormat) -> DeviceInfo {
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
    /// The same plugin found in two places is registered once (the first).
    const ONE_PER_ID: bool;
    /// The file in `bundle` that the cache is keyed by, or `None` to pass
    /// the bundle over.
    fn library(bundle: &Path) -> Option<PathBuf>;
    /// The usual folders of the format in `dirs`.
    fn usual(dirs: &PluginDirs) -> &[PathBuf];
    /// Load `bundle` and list the plugins in it, in this process. The
    /// libraries that it needs are looked for in `libraries`.
    fn list(bundle: &Path, libraries: &[PathBuf]) -> anyhow::Result<Vec<Found>>;
    /// The device kind of a plugin, unique in `registry`.
    fn kind(found: &Found, registry: &Registry) -> String;
    /// The factory of a plugin found in `bundle`, or `None` when its id is
    /// not one the format can use. `dirs` gives the folders that the
    /// plugin's load and presets need.
    fn factory(
        info: DeviceInfo,
        bundle: &Path,
        dirs: &PluginDirs,
    ) -> Option<Rc<dyn DeviceFactory>>;
}

/// Register the plugins of format `F` found where that format is installed:
/// its usual folders in `dirs`, then the folders added.
pub(crate) fn scan<F: PluginFormat>(
    registry: &mut Registry,
    cache: &mut Cache,
    notes: &mut Vec<String>,
    dirs: &PluginDirs,
) {
    scan_in::<F>(registry, cache, notes, dirs, &dirs.search(F::usual(dirs)));
}

/// Register the plugins of format `F` in the files under `folders`. `dirs`
/// gives the folders of the libraries and presets that the plugins need.
pub(crate) fn scan_in<F: PluginFormat>(
    registry: &mut Registry,
    cache: &mut Cache,
    notes: &mut Vec<String>,
    dirs: &PluginDirs,
    folders: &[PathBuf],
) {
    // The ids of the format that `registry` holds count as found already.
    let mut seen: std::collections::HashSet<String> = registry
        .iter()
        .map(|factory| factory.info())
        .filter(|info| info.format == F::FORMAT)
        .map(|info| info.id.clone())
        .collect();
    for bundle in find_bundles(folders, F::NAME) {
        let Some(library) = F::library(&bundle) else {
            continue;
        };
        match cache.plugins(&library, || {
            list_apart(F::NAME, &bundle, || F::list(&bundle, &dirs.libraries))
        }) {
            Ok(found) => {
                for plugin in found {
                    if F::ONE_PER_ID && !seen.insert(plugin.id.clone()) {
                        continue;
                    }
                    let kind = F::kind(&plugin, registry);
                    let info = plugin.device_info(kind, F::FORMAT);
                    if let Some(factory) = F::factory(info, &bundle, dirs) {
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
    pub(crate) fn mark_changed(&mut self) {
        self.changed = true;
    }

    /// The plugins in `path`, calling `scan` only if the file is new or has
    /// changed since it was last scanned.
    pub(crate) fn plugins(
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
/// format and the file, and `dirs` says where the libraries that it needs
/// are. The answer is the last line it prints.
pub fn scan_main(args: &[String], dirs: &PluginDirs) -> i32 {
    MAIN_THREAD.get_or_init(|| std::thread::current().id());
    let libraries = &dirs.libraries;
    let found: Result<Vec<Found>, String> = match args {
        [format, path] if format == "vst3" => vst3::list_file(Path::new(path), libraries),
        [format, path] if format == "clap" => clap::list_file(Path::new(path), libraries),
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

/// Every entry under `dirs` whose name ends in `extension`, searching
/// subdirectories but not inside matches. The entries come in the order of
/// `dirs`, and in the order of their paths in each. So the first folder
/// wins where two plugins share an id or a name, and a folder added later
/// never changes the kinds of the plugins found before it: a helper process,
/// which scans all folders at once, gives the kinds that the adds gave. An
/// entry found two times comes once, at its first place.
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
    let mut seen = std::collections::HashSet::new();
    for dir in dirs {
        let mut found = Vec::new();
        walk(dir, extension, 0, &mut found);
        found.sort();
        out.extend(found.into_iter().filter(|path| seen.insert(path.clone())));
    }
    out
}

/// Parts which notes are sounding, so that "all notes off" can be sent as
/// the individual note-offs every plugin understands.
pub(crate) struct HeldNotes {
    /// The channels each key sounds on, one bit each.
    held: [u16; 128],
}

impl HeldNotes {
    pub(crate) fn new() -> Self {
        Self { held: [0; 128] }
    }

    /// Feed the block's events through, calling `emit` for each note event
    /// with "all notes off" expanded.
    pub(crate) fn expand(&mut self, events: &[Event], mut emit: impl FnMut(u32, EventKind)) {
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

/// How a plugin's output goes onto the part's two channels.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Mix {
    /// Added to what is on the part: an instrument, which has no audio input.
    Add,
    /// In place of what is on the part: an effect.
    Replace,
}

impl Mix {
    /// The mix of a plugin with audio inputs or none.
    pub(crate) fn for_inputs(has_inputs: bool) -> Self {
        if has_inputs { Self::Replace } else { Self::Add }
    }
}

/// Copy a plugin's stereo, mono or wider output into the part's two channels.
pub(crate) fn write_output(left: &mut [f32], right: &mut [f32], out: &[&[f32]], mix: Mix) {
    let (Some(l), Some(r)) = (out.first(), out.get(1).or(out.first())) else {
        return;
    };
    for (i, (dl, dr)) in left.iter_mut().zip(right.iter_mut()).enumerate() {
        match mix {
            Mix::Add => {
                *dl += l[i];
                *dr += r[i];
            }
            Mix::Replace => {
                *dl = l[i];
                *dr = r[i];
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A file in `dir` that ends in `.clap` and is no plugin: the scan
    /// notes each one that it finds, and loads nothing.
    fn broken_plugin(dir: &Path, name: &str) -> PathBuf {
        std::fs::create_dir_all(dir).unwrap();
        let file = dir.join(name);
        std::fs::write(&file, b"not a shared library").unwrap();
        file
    }

    #[test]
    fn the_scan_searches_the_usual_folders_and_the_added_ones_only() {
        let root = tempfile::tempdir().unwrap();
        let usual = broken_plugin(&root.path().join("clap"), "usual.clap");
        let added = broken_plugin(&root.path().join("extension"), "added.clap");
        broken_plugin(&root.path().join("elsewhere"), "elsewhere.clap");
        let mut dirs = PluginDirs {
            clap: vec![root.path().join("clap")],
            ..PluginDirs::default()
        };
        dirs.add(added.parent().unwrap());

        let mut registry = Registry::default();
        let (mut cache, mut notes) = (Cache::load(None), Vec::new());
        scan::<clap::Clap>(&mut registry, &mut cache, &mut notes, &dirs);

        let noted: Vec<bool> = [&usual, &added]
            .iter()
            .map(|file| notes.iter().any(|note| note.starts_with(&*file.to_string_lossy())))
            .collect();
        assert_eq!(noted, [true, true], "both folders are searched: {notes:?}");
        assert_eq!(notes.len(), 2, "no other folder is searched: {notes:?}");
        assert_eq!(registry.iter().count(), 0, "no plugin is registered");
    }

    /// A VST3 bundle `<name>.vst3` in `dir` with one plugin, `name` with
    /// the class `id`, which the cache in `cache_file` knows already: a scan
    /// registers it and loads nothing. The cache also knows that there are
    /// no LV2 plugins.
    fn known_vst3(dir: &Path, cache_file: &Path, name: &str, id: &str) {
        let library = dir
            .join(format!("{name}.vst3/Contents/{}-linux", std::env::consts::ARCH))
            .join(format!("{name}.so"));
        std::fs::create_dir_all(library.parent().unwrap()).unwrap();
        std::fs::write(&library, b"never loaded").unwrap();
        let real = std::fs::canonicalize(&library).unwrap();
        let (modified, size) = stamp(&real);
        let found = Found {
            id: id.into(),
            name: name.into(),
            vendor: String::new(),
            instrument: true,
            version: String::new(),
            features: Vec::new(),
        };
        let mut cache = Cache::load(Some(cache_file));
        cache.files.insert(
            real,
            CachedFile {
                modified,
                size,
                plugins: Ok(vec![found]),
            },
        );
        cache.lv2 = Some(Lv2Cache {
            bundles: Vec::new(),
            plugins: Vec::new(),
            skipped: 0,
        });
        cache.write();
    }

    const ONE: &str = "11111111111111111111111111111111";
    const TWO: &str = "22222222222222222222222222222222";

    /// The VST3 kinds in `registry`, each with the class of its plugin.
    fn vst3_kinds(registry: &Registry) -> Vec<(String, String)> {
        registry
            .iter()
            .map(|factory| factory.info())
            .filter(|info| info.format == DeviceFormat::Vst3)
            .map(|info| (info.kind.clone(), info.id.clone()))
            .collect()
    }

    /// The VST3 kinds that a helper process finds with `dirs`: it registers
    /// the plugins in a new registry.
    fn helper_kinds(cache_file: &Path, dirs: &PluginDirs) -> Vec<(String, String)> {
        let mut helper = Registry::default();
        register(&mut helper, Some(cache_file), dirs);
        vst3_kinds(&helper)
    }

    #[test]
    fn a_rescan_gives_each_plugin_the_kind_that_a_helper_gives_it() {
        let root = tempfile::tempdir().unwrap();
        let cache_file = root.path().join("plugins.json");
        known_vst3(&root.path().join("vst3"), &cache_file, "Same", ONE);
        let dirs = PluginDirs {
            vst3: vec![root.path().join("vst3")],
            ..PluginDirs::default()
        };
        let mut registry = Registry::with_builtins();
        register(&mut registry, Some(&cache_file), &dirs);

        rescan(&mut registry, Some(&cache_file), Some("no such plugin"), &dirs);

        let kinds = vst3_kinds(&registry);
        assert_eq!(kinds, [("vst3:Same".to_string(), ONE.to_string())], "the plugin once");
        assert_eq!(kinds, helper_kinds(&cache_file, &dirs), "as a helper names it");
        assert!(registry.get("synth").is_some(), "the built-in devices stay");
    }

    #[test]
    fn a_plugin_in_an_added_folder_gets_the_kind_that_a_helper_gives_it() {
        let root = tempfile::tempdir().unwrap();
        let cache_file = root.path().join("plugins.json");
        let (usual, added) = (root.path().join("vst3"), root.path().join("extension"));
        known_vst3(&usual, &cache_file, "Same", ONE);
        let mut dirs = PluginDirs {
            vst3: vec![usual],
            ..PluginDirs::default()
        };
        let mut registry = Registry::default();
        register(&mut registry, Some(&cache_file), &dirs);
        // Another plugin with the name of the first, and a copy of the first.
        known_vst3(&added, &cache_file, "Same", TWO);
        known_vst3(&added, &cache_file, "Copy", ONE);

        let (kinds, notes) = add_dir(&mut registry, Some(&cache_file), &mut dirs, &added);

        assert_eq!(kinds, ["vst3:Same (2)"], "the new plugin only ({notes:?})");
        assert_eq!(
            vst3_kinds(&registry),
            helper_kinds(&cache_file, &dirs),
            "each kind names the plugin that a helper makes of it"
        );
    }
}
