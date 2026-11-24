//! A plugin's own presets, where its format says how to find them: CLAP's
//! preset discovery and preset-load extension, VST3 `.vstpreset` files in the
//! standard directories, LV2 presets (in `lv2/controller.rs`, through lilv).
//!
//! Each format's controller answers two calls with these: `presets` gives a
//! JSON list of `{ id, name, category }`, and `preset.load` takes an `id`
//! from it. Ids are stable across runs, so a project or a script can keep one.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_possible_wrap, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use crate::bytes::{le_i32, le_i64};
use std::cell::Cell;
use std::ffi::{CStr, CString, c_char, c_void};
use std::path::{Path, PathBuf};
use std::ptr;

use anyhow::{Context, Result};
use clack_extensions::preset_discovery::factory::PresetDiscoveryFactory;
use clack_extensions::preset_discovery::indexer::IndexerImpl;
use clack_extensions::preset_discovery::metadata_receiver::MetadataReceiverImpl;
use clack_extensions::preset_discovery::preset_data::{
    FileType, Flags, Location, LocationInfo, Soundpack,
};
use clack_extensions::preset_discovery::provider::Provider;
use clack_host::entry::{EntryDescriptor, PluginEntry};
use clack_host::factory::{Factory, RawFactoryPointer};
use clack_host::prelude::{HostError, HostInfo};
use clack_host::utils::{Timestamp, UniversalPluginId};
use clap_sys::factory::preset_discovery::{
    CLAP_PRESET_DISCOVERY_FACTORY_ID, CLAP_PRESET_DISCOVERY_FACTORY_ID_COMPAT,
    clap_preset_discovery_factory,
};
use clap_sys::version::CLAP_VERSION;
use serde_json::{Value, json};

/// One preset, as listed to the host.
#[derive(Clone, Debug, PartialEq)]
pub struct Preset {
    pub id: String,
    pub name: String,
    pub category: String,
}

pub fn to_json(presets: &[Preset]) -> Vec<u8> {
    let list: Vec<Value> = presets
        .iter()
        .map(|p| json!({ "id": p.id, "name": p.name, "category": p.category }))
        .collect();
    serde_json::to_vec(&list).unwrap_or_default()
}

/// Files under `dir` (recursively, not following links forever) whose
/// extension is one of `extensions` (any when empty), up to `limit`.
fn files_under(dir: &Path, extensions: &[String], limit: usize, out: &mut Vec<PathBuf>) {
    let mut stack = vec![(dir.to_path_buf(), 0)];
    while let Some((dir, depth)) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        let mut entries: Vec<_> = entries.flatten().map(|e| e.path()).collect();
        entries.sort();
        for path in entries.into_iter().rev() {
            if out.len() >= limit {
                return;
            }
            if path.is_dir() {
                if depth < 8 {
                    stack.push((path, depth + 1));
                }
            } else {
                let ext = path
                    .extension()
                    .map(|e| e.to_string_lossy().to_lowercase())
                    .unwrap_or_default();
                if extensions.is_empty() || extensions.contains(&ext) {
                    out.push(path);
                }
            }
        }
    }
    out.sort();
}

/// The folder a preset is in, relative to where its location starts: what
/// the list shows as its category.
fn category(root: &Path, file: &Path) -> String {
    file.parent()
        .and_then(|parent| parent.strip_prefix(root).ok())
        .map(|rel| rel.to_string_lossy().into_owned())
        .unwrap_or_default()
}

// --- CLAP ---------------------------------------------------------------------

/// Separates the parts of a CLAP preset's id: location kind, location, load key.
const SEP: char = '\u{1f}';

/// What a provider declares when it starts: the file types and locations
/// of its presets.
#[derive(Default)]
struct Indexer {
    extensions: Vec<String>,
    /// Each location, with its path (none for the plugin's own presets).
    locations: Vec<(u32, Option<String>)>,
}

impl IndexerImpl for Indexer {
    fn declare_filetype(&mut self, file_type: FileType) -> Result<(), HostError> {
        let ext = file_type
            .file_extension
            .map(|e| e.to_string_lossy().to_lowercase())
            .unwrap_or_default();
        if !ext.is_empty() {
            self.extensions.push(ext);
        }
        Ok(())
    }

    fn declare_location(&mut self, location: LocationInfo) -> Result<(), HostError> {
        let path = location
            .location
            .file_path()
            .map(|p| p.to_string_lossy().into_owned());
        self.locations.push((kind(location.location), path));
        Ok(())
    }

    fn declare_soundpack(&mut self, _: Soundpack) -> Result<(), HostError> {
        Ok(())
    }
}

/// The number of a location's kind, as preset ids keep it.
const fn kind(location: Location) -> u32 {
    location.to_raw().0
}
const PLUGIN: u32 = kind(Location::Plugin);
const FILE: u32 = kind(Location::File { path: c"" });

/// Takes the presets of one location as the provider describes them.
#[derive(Default)]
struct Receiver {
    /// Where the presets being received now are.
    kind: u32,
    location: String,
    root: PathBuf,
    /// The presets received, with the plugin ids each says it is for.
    presets: Vec<(Preset, Vec<String>)>,
}

impl MetadataReceiverImpl for Receiver {
    fn on_error(&mut self, _: i32, _: Option<&CStr>) {}

    fn begin_preset(&mut self, name: Option<&CStr>, load_key: Option<&CStr>) -> Result<(), HostError> {
        let text = |s: Option<&CStr>| s.map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
        let key = text(load_key);
        let id = format!("{}{SEP}{}{SEP}{}", self.kind, self.location, key);
        let mut name = text(name);
        let file = Path::new(&self.location);
        if name.is_empty() {
            name = file
                .file_stem()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_else(|| key.clone());
        }
        let category = if self.kind == FILE {
            category(&self.root, file)
        } else {
            String::new()
        };
        self.presets.push((Preset { id, name, category }, Vec::new()));
        Ok(())
    }

    fn add_plugin_id(&mut self, plugin_id: UniversalPluginId) {
        if let Some(last) = self.presets.last_mut() {
            last.1.push(plugin_id.id.to_string_lossy().into_owned());
        }
    }

    fn set_soundpack_id(&mut self, _: &CStr) {}
    fn set_flags(&mut self, _: Flags) {}
    fn add_creator(&mut self, _: &CStr) {}
    fn set_description(&mut self, _: &CStr) {}
    fn set_timestamps(&mut self, _: Option<Timestamp>, _: Option<Timestamp>) {}
    fn add_feature(&mut self, _: &CStr) {}
    fn add_extra_info(&mut self, _: &CStr, _: &CStr) {}
}

/// The presets the plugin file's preset-discovery providers know of for
/// the plugin `plugin_id`. Runs on the main thread.
pub fn clap_presets(entry: &PluginEntry, plugin_id: &str) -> Vec<Preset> {
    let mut out = Vec::new();
    let Ok(host) = HostInfo::new("paw", "paw", "", "0.1.0") else {
        return out;
    };
    // A file that has only the draft factory is seen through an entry that
    // answers for it under the final id.
    let draft;
    let entry = match draft_entry(entry) {
        Some(entry) => {
            draft = entry;
            &draft
        }
        None => entry,
    };
    let Some(factory) = entry.get_factory::<PresetDiscoveryFactory>() else {
        return out;
    };
    for desc in factory.provider_descriptors() {
        let Some(provider_id) = desc.id() else {
            continue;
        };
        let Ok(mut provider) = Provider::instantiate(Indexer::default(), entry, provider_id, &host)
        else {
            continue;
        };
        let indexer = std::mem::take(provider.indexer_mut());
        let mut receiver = Receiver::default();
        for (kind, location) in indexer.locations {
            if kind == PLUGIN {
                receiver.kind = kind;
                receiver.location.clear();
                receiver.root = PathBuf::new();
                provider.get_metadata(Location::Plugin, &mut receiver);
                continue;
            }
            let Some(location) = location else { continue };
            let root = PathBuf::from(&location);
            let mut files = Vec::new();
            if root.is_dir() {
                files_under(&root, &indexer.extensions, 20_000, &mut files);
            } else {
                files.push(root.clone());
            }
            for file in files {
                let Ok(c_path) = CString::new(file.to_string_lossy().as_bytes()) else {
                    continue;
                };
                receiver.kind = kind;
                receiver.location = file.to_string_lossy().into_owned();
                receiver.root = root.clone();
                provider.get_metadata(Location::File { path: &c_path }, &mut receiver);
            }
        }
        drop(provider);
        out.extend(
            receiver
                .presets
                .into_iter()
                .filter(|(_, ids)| ids.is_empty() || ids.iter().any(|id| id == plugin_id))
                .map(|(preset, _)| preset),
        );
    }
    out
}

/// The preset-discovery factory under its draft id, which Clack's
/// [`PluginEntry::get_factory`] does not ask for: it asks only for the
/// final one.
#[derive(Clone, Copy)]
struct DraftFactory<'a>(RawFactoryPointer<'a, clap_preset_discovery_factory>);

// SAFETY: The draft id names the same table as the final one, `clap_preset_discovery_factory`.
unsafe impl<'a> Factory<'a> for DraftFactory<'a> {
    const IDENTIFIERS: &'static [&'static CStr] = &[CLAP_PRESET_DISCOVERY_FACTORY_ID_COMPAT];
    type Raw = clap_preset_discovery_factory;

    unsafe fn from_raw(raw: RawFactoryPointer<'a, Self::Raw>) -> Self {
        Self(raw)
    }
}

thread_local! {
    /// The draft factory that [`DRAFT_ENTRY`] gives now, or null.
    static DRAFT: Cell<*const c_void> = const { Cell::new(ptr::null()) };
}

/// An entry with no plugins whose preset-discovery factory is [`DRAFT`]:
/// how a provider of a file that has only the draft factory is made
/// through Clack, which finds the factory through an entry and only by the
/// final id.
static DRAFT_ENTRY: EntryDescriptor = EntryDescriptor {
    clap_version: CLAP_VERSION,
    init: Some(draft_init),
    deinit: Some(draft_deinit),
    get_factory: Some(draft_get_factory),
};

unsafe extern "C" fn draft_init(_: *const c_char) -> bool {
    true
}

unsafe extern "C" fn draft_deinit() {}

unsafe extern "C" fn draft_get_factory(id: *const c_char) -> *const c_void {
    // SAFETY: Clack calls this with a NUL-terminated factory id that lives for the call.
    let id = unsafe { CStr::from_ptr(id) };
    if id == CLAP_PRESET_DISCOVERY_FACTORY_ID {
        DRAFT.get()
    } else {
        ptr::null()
    }
}

/// When `entry` has the draft preset-discovery factory and not the final
/// one, an entry that answers with it under the final id, for this thread
/// until the scan of the next file.
fn draft_entry(entry: &PluginEntry) -> Option<PluginEntry> {
    if entry.get_factory::<PresetDiscoveryFactory>().is_some() {
        return None;
    }
    let draft = entry.get_factory::<DraftFactory>()?;
    DRAFT.set(draft.0.as_ptr().cast_const().cast());
    // SAFETY: `DRAFT_ENTRY` is static, its `init` and `deinit` do nothing, and its factory is
    // the draft factory of `entry`'s file, which is never unloaded (see clap/library.rs's `Library`).
    unsafe { PluginEntry::load_from_raw(&DRAFT_ENTRY, c"paw-draft-presets") }.ok()
}

/// Where a CLAP preset is: what [`clap_preset_parts`] reads from its id.
#[derive(Debug, PartialEq)]
pub enum PresetLocation {
    /// Inside the plugin.
    Plugin,
    /// In a file.
    File(CString),
}

impl PresetLocation {
    pub fn as_location(&self) -> Location<'_> {
        match self {
            Self::Plugin => Location::Plugin,
            Self::File(path) => Location::File { path },
        }
    }
}

/// The parts of a CLAP preset id: its location (none when the kind is not
/// one paw knows) and load key (none when there is none).
pub fn clap_preset_parts(id: &str) -> Result<(Option<PresetLocation>, Option<CString>)> {
    // A file named by a script: `file:<path>`.
    if let Some(path) = id.strip_prefix("file:").filter(|p| !p.is_empty()) {
        return Ok((Some(PresetLocation::File(CString::new(path)?)), None));
    }
    let mut parts = id.splitn(3, SEP);
    let kind: u32 = parts
        .next()
        .and_then(|k| k.parse().ok())
        .context("not a preset of this plugin")?;
    let location = parts.next().unwrap_or_default();
    let key = parts.next().unwrap_or_default();
    let c = |s: &str| -> Result<Option<CString>> {
        Ok(if s.is_empty() {
            None
        } else {
            Some(CString::new(s)?)
        })
    };
    let location = c(location)?;
    let location = if kind == PLUGIN {
        Some(PresetLocation::Plugin)
    } else if kind == FILE {
        Some(PresetLocation::File(
            location.context("not a preset of this plugin")?,
        ))
    } else {
        None
    };
    Ok((location, c(key)?))
}

// --- VST3 ---------------------------------------------------------------------

/// Where `.vstpreset` files are kept for a plugin, as the VST3 SDK sets out
/// for Linux: `<root>/<vendor>/<plugin>` for each of `roots` in order
/// ([`crate::PluginDirs`] gives `$VST3_PRESET_PATH`, then
/// `~/.vst3/presets`, then the system's), then the presets shipped inside
/// the plugin's bundle. Only the folders that exist.
pub fn vst3_preset_dirs(
    roots: &[PathBuf],
    vendor: &str,
    plugin: &str,
    bundle: Option<&Path>,
) -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = roots
        .iter()
        .map(|root| root.join(vendor).join(plugin))
        .collect();
    if let Some(bundle) = bundle {
        dirs.push(bundle.join("Contents/Resources/Presets"));
    }
    dirs.retain(|d| d.is_dir());
    dirs
}

/// Every `.vstpreset` under the directories, named by file and grouped by
/// the folder each is in. The id is the file's path.
pub fn vst3_presets(dirs: &[PathBuf]) -> Vec<Preset> {
    let mut out = Vec::new();
    for dir in dirs {
        let mut files = Vec::new();
        files_under(dir, &["vstpreset".into()], 20_000, &mut files);
        for file in files {
            out.push(Preset {
                id: file.to_string_lossy().into_owned(),
                name: file
                    .file_stem()
                    .map(|s| s.to_string_lossy().into_owned())
                    .unwrap_or_default(),
                category: category(dir, &file),
            });
        }
    }
    out
}

/// A `.vstpreset` file's class id and its component and controller states
/// (the `Comp` and `Cont` chunks; either may be empty).
pub fn read_vstpreset(bytes: &[u8]) -> Result<(String, Vec<u8>, Vec<u8>)> {
    let short = || anyhow::anyhow!("not a VST3 preset file");
    if bytes.len() < 48 || &bytes[..4] != b"VST3" {
        return Err(short());
    }
    let class = String::from_utf8_lossy(&bytes[8..40]).into_owned();
    let list_at = le_i64(bytes, 40).and_then(|at| usize::try_from(at).ok()).ok_or_else(short)?;
    let list = bytes.get(list_at..).ok_or_else(short)?;
    if list.len() < 8 || &list[..4] != b"List" {
        return Err(short());
    }
    let count = le_i32(list, 4).and_then(|n| usize::try_from(n).ok()).ok_or_else(short)?;
    let (mut comp, mut cont) = (Vec::new(), Vec::new());
    for i in 0..count {
        let entry = list.get(8 + i * 20..8 + (i + 1) * 20).ok_or_else(short)?;
        let offset = le_i64(entry, 4).and_then(|at| usize::try_from(at).ok()).ok_or_else(short)?;
        let size = le_i64(entry, 12).and_then(|n| usize::try_from(n).ok()).ok_or_else(short)?;
        let data = bytes
            .get(offset..offset.checked_add(size).ok_or_else(short)?)
            .ok_or_else(short)?
            .to_vec();
        match &entry[..4] {
            b"Comp" => comp = data,
            b"Cont" => cont = data,
            _ => {}
        }
    }
    Ok((class, comp, cont))
}

/// A `.vstpreset` file made of a class id and the two states: what
/// [`read_vstpreset`] reads.
pub fn write_vstpreset(class: &str, comp: &[u8], cont: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(b"VST3");
    out.extend_from_slice(&1i32.to_le_bytes());
    let mut id = class.as_bytes().to_vec();
    id.resize(32, b'0');
    out.extend_from_slice(&id);
    let list_at = 48 + comp.len() + cont.len();
    out.extend_from_slice(&(list_at as i64).to_le_bytes());
    out.extend_from_slice(comp);
    out.extend_from_slice(cont);
    out.extend_from_slice(b"List");
    out.extend_from_slice(&2i32.to_le_bytes());
    for (tag, at, size) in [
        (b"Comp", 48, comp.len()),
        (b"Cont", 48 + comp.len(), cont.len()),
    ] {
        out.extend_from_slice(tag);
        out.extend_from_slice(&(at as i64).to_le_bytes());
        out.extend_from_slice(&(size as i64).to_le_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vst3_presets_are_looked_for_under_each_root_in_order_then_in_the_bundle() {
        let root = tempfile::tempdir().unwrap();
        let folder = |rel: &str| {
            let dir = root.path().join(rel);
            std::fs::create_dir_all(&dir).unwrap();
            dir
        };
        let first = folder("first/Vendor/Plugin");
        let second = folder("second/Vendor/Plugin");
        let shipped = folder("Plugin.vst3/Contents/Resources/Presets");
        folder("second/Vendor/Other");
        let roots = [
            root.path().join("second"),
            root.path().join("none"),
            root.path().join("first"),
        ];

        let bundle = root.path().join("Plugin.vst3");
        let dirs = vst3_preset_dirs(&roots, "Vendor", "Plugin", Some(&bundle));

        assert_eq!(
            dirs,
            [second, first, shipped],
            "the folders that exist, in the order of the roots"
        );
    }

    #[test]
    fn vstpreset_round_trips() {
        let file = write_vstpreset("0123456789ABCDEF0123456789ABCDEF", b"component", b"ctl");
        let (class, comp, cont) = read_vstpreset(&file).unwrap();
        assert_eq!(class, "0123456789ABCDEF0123456789ABCDEF");
        assert_eq!(comp, b"component");
        assert_eq!(cont, b"ctl");
        assert!(read_vstpreset(b"nothing").is_err());
    }

    #[test]
    fn clap_ids_split_into_their_parts() {
        let (location, key) = clap_preset_parts("0\u{1f}/a/b.fxp\u{1f}").unwrap();
        assert_eq!(location, Some(PresetLocation::File(c"/a/b.fxp".into())));
        assert!(key.is_none());
        assert!(clap_preset_parts("junk").is_err());
    }
}
