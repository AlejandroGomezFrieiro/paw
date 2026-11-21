//! A plugin's own presets, where its format says how to find them: CLAP's
//! preset discovery and preset-load extension, VST3 `.vstpreset` files in the
//! standard directories, LV2 presets (in `lv2/controller.rs`, through lilv).
//!
//! Each format's controller answers two calls with these: `presets` gives a
//! JSON list of `{ id, name, category }`, and `preset.load` takes an `id`
//! from it. Ids are stable across runs, so a project or a script can keep one.

use std::ffi::{CStr, CString, c_char, c_void};
use std::path::{Path, PathBuf};
use std::ptr;

use anyhow::{Context, Result, bail};
use clap_sys::factory::preset_discovery::*;
use clap_sys::universal_plugin_id::clap_universal_plugin_id;
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

/// What the indexer and the metadata receiver collect.
#[derive(Default)]
struct Found {
    extensions: Vec<String>,
    locations: Vec<(u32, Option<String>, String)>,
    /// Where the presets being received now are.
    kind: u32,
    location: String,
    root: PathBuf,
    /// The presets received, with the plugin ids each says it is for.
    presets: Vec<(Preset, Vec<String>)>,
}

unsafe fn text(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        // SAFETY: `ptr` is non-null (checked above) and `text` requires (its # Safety) a NUL-terminated
        // string that stays valid for the call; the bytes are copied out before it returns.
        unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned()
    }
}

unsafe fn found<'a>(data: *mut c_void) -> &'a mut Found {
    // SAFETY: `data` is the `indexer_data` or `receiver_data` that `scan_provider` set to a live
    // `Box<Found>` that outlives the provider, and the plugin calls back one at a time on the
    // thread that called it, so no other reference to the Found exists.
    unsafe { &mut *(data as *mut Found) }
}

unsafe extern "C" fn declare_filetype(
    indexer: *const clap_preset_discovery_indexer,
    filetype: *const clap_preset_discovery_filetype,
) -> bool {
    // SAFETY: The plugin calls this with the indexer it was given in `create` (alive during
    // the scan) and a filetype it owns for the call; `indexer_data` is the Found (see `found`).
    unsafe {
        let found = found((*indexer).indexer_data);
        if let Some(filetype) = filetype.as_ref() {
            let ext = text(filetype.file_extension).to_lowercase();
            if !ext.is_empty() {
                found.extensions.push(ext);
            }
        }
        true
    }
}

unsafe extern "C" fn declare_location(
    indexer: *const clap_preset_discovery_indexer,
    location: *const clap_preset_discovery_location,
) -> bool {
    // SAFETY: The plugin passes the indexer given to it in `create`, which holds our Found in
    // `indexer_data`, and a location it owns for the duration of the call; strings are NUL-terminated.
    unsafe {
        let found = found((*indexer).indexer_data);
        if let Some(l) = location.as_ref() {
            let path = (!l.location.is_null()).then(|| text(l.location));
            found.locations.push((l.kind, path, text(l.name)));
        }
        true
    }
}

unsafe extern "C" fn declare_soundpack(
    _: *const clap_preset_discovery_indexer,
    _: *const clap_preset_discovery_soundpack,
) -> bool {
    true
}

unsafe extern "C" fn indexer_extension(
    _: *const clap_preset_discovery_indexer,
    _: *const c_char,
) -> *const c_void {
    ptr::null()
}

unsafe extern "C" fn on_error(
    _: *const clap_preset_discovery_metadata_receiver,
    _: i32,
    _: *const c_char,
) {
}

unsafe extern "C" fn begin_preset(
    receiver: *const clap_preset_discovery_metadata_receiver,
    name: *const c_char,
    load_key: *const c_char,
) -> bool {
    // SAFETY: The plugin passes the metadata receiver given to it, whose `receiver_data` is our Found;
    // `name` and `load_key` are NUL-terminated strings (or null) it owns for the call.
    unsafe {
        let found = found((*receiver).receiver_data);
        let key = text(load_key);
        let id = format!("{}{SEP}{}{SEP}{}", found.kind, found.location, key);
        let mut name = text(name);
        let root = found.root.clone();
        let file = Path::new(&found.location);
        if name.is_empty() {
            name = file
                .file_stem()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_else(|| key.clone());
        }
        let category = if found.kind == CLAP_PRESET_DISCOVERY_LOCATION_FILE {
            category(&root, file)
        } else {
            String::new()
        };
        found
            .presets
            .push((Preset { id, name, category }, Vec::new()));
        true
    }
}

unsafe extern "C" fn add_plugin_id(
    receiver: *const clap_preset_discovery_metadata_receiver,
    plugin_id: *const clap_universal_plugin_id,
) {
    // SAFETY: The plugin passes the receiver given to it (`receiver_data` is our Found), and the
    // plugin id it owns for the call; null pointers are handled by as_ref and `text`.
    unsafe {
        let found = found((*receiver).receiver_data);
        if let (Some(last), Some(id)) = (found.presets.last_mut(), plugin_id.as_ref()) {
            last.1.push(text(id.id));
        }
    }
}

unsafe extern "C" fn ignore_text(
    _: *const clap_preset_discovery_metadata_receiver,
    _: *const c_char,
) {
}
unsafe extern "C" fn ignore_flags(_: *const clap_preset_discovery_metadata_receiver, _: u32) {}
unsafe extern "C" fn ignore_times(
    _: *const clap_preset_discovery_metadata_receiver,
    _: u64,
    _: u64,
) {
}
unsafe extern "C" fn ignore_pair(
    _: *const clap_preset_discovery_metadata_receiver,
    _: *const c_char,
    _: *const c_char,
) {
}

/// The presets the plugin file's preset-discovery providers know of for
/// the plugin `plugin_id`. `factory` is what the file's entry gave for
/// the preset-discovery factory id, or null.
///
/// # Safety
/// `factory` must be null or a preset-discovery factory of a loaded file,
/// and this runs on the main thread.
pub unsafe fn clap_presets(
    factory: *const clap_preset_discovery_factory,
    plugin_id: &str,
) -> Vec<Preset> {
    let mut out = Vec::new();
    // SAFETY: The caller got `factory` from the plugin's entry for this call, so it is null or a live factory.
    let Some(f) = (unsafe { factory.as_ref() }) else {
        return out;
    };
    let (Some(count), Some(get), Some(create)) = (f.count, f.get_descriptor, f.create) else {
        return out;
    };
    // SAFETY: `count` is the factory's own function, called with the factory it belongs to.
    for index in 0..unsafe { count(factory) } {
        // SAFETY: `get` is the factory's function, called with the factory and an index below `count`;
        // the descriptor it returns is null or valid as long as the factory.
        let Some(desc) = (unsafe { get(factory, index).as_ref() }) else {
            continue;
        };
        let mut data = Box::new(Found::default());
        let indexer = clap_preset_discovery_indexer {
            clap_version: CLAP_VERSION,
            name: c"paw".as_ptr(),
            vendor: c"paw".as_ptr(),
            url: c"".as_ptr(),
            version: c"0.1.0".as_ptr(),
            indexer_data: &mut *data as *mut Found as *mut c_void,
            declare_filetype: Some(declare_filetype),
            declare_location: Some(declare_location),
            declare_soundpack: Some(declare_soundpack),
            get_extension: Some(indexer_extension),
        };
        // SAFETY: `create` is the factory's function; `factory` is live, `indexer` lives on this stack frame
        // until the provider is destroyed below, and `desc.id` is the descriptor's own NUL-terminated id.
        let provider = unsafe { create(factory, &indexer, desc.id) };
        // SAFETY: `create` returns null or a provider that stays valid until `destroy`.
        let Some(p) = (unsafe { provider.as_ref() }) else {
            continue;
        };
        // SAFETY: `init` is the provider's function, called once with its own provider, before any other call.
        if !p.init.is_some_and(|init| unsafe { init(provider) }) {
            if let Some(destroy) = p.destroy {
                // SAFETY: `destroy` is the provider's function; the provider is not used again (the loop `continue`s).
                unsafe { destroy(provider) };
            }
            continue;
        }
        let receiver = clap_preset_discovery_metadata_receiver {
            receiver_data: &mut *data as *mut Found as *mut c_void,
            on_error: Some(on_error),
            begin_preset: Some(begin_preset),
            add_plugin_id: Some(add_plugin_id),
            set_soundpack_id: Some(ignore_text),
            set_flags: Some(ignore_flags),
            add_creator: Some(ignore_text),
            set_description: Some(ignore_text),
            set_timestamps: Some(ignore_times),
            add_feature: Some(ignore_text),
            add_extra_info: Some(ignore_pair),
        };
        let locations = std::mem::take(&mut data.locations);
        let extensions = data.extensions.clone();
        if let Some(get_metadata) = p.get_metadata {
            for (kind, location, _) in locations {
                if kind == CLAP_PRESET_DISCOVERY_LOCATION_PLUGIN {
                    data.kind = kind;
                    data.location.clear();
                    data.root = PathBuf::new();
                    // SAFETY: `get_metadata` is the provider's function, called after a successful `init` with its own
                    // provider and a receiver that lives on this stack frame for the call; a null path means the plugin's own presets.
                    unsafe { get_metadata(provider, kind, ptr::null(), &receiver) };
                    continue;
                }
                let Some(location) = location else { continue };
                let root = PathBuf::from(&location);
                let mut files = Vec::new();
                if root.is_dir() {
                    files_under(&root, &extensions, 20_000, &mut files);
                } else {
                    files.push(root.clone());
                }
                for file in files {
                    let Ok(c_path) = CString::new(file.to_string_lossy().as_bytes()) else {
                        continue;
                    };
                    data.kind = kind;
                    data.location = file.to_string_lossy().into_owned();
                    data.root = root.clone();
                    // SAFETY: `get_metadata` is the provider's function, called after a successful `init`; `c_path` is
                    // a CString that lives through the call and `receiver` lives on this stack frame.
                    unsafe { get_metadata(provider, kind, c_path.as_ptr(), &receiver) };
                }
            }
        }
        if let Some(destroy) = p.destroy {
            // SAFETY: `destroy` is called once for a provider that was created and initialized here, after
            // its last use, and the provider is not touched afterwards.
            unsafe { destroy(provider) };
        }
        out.extend(
            data.presets
                .drain(..)
                .filter(|(_, ids)| ids.is_empty() || ids.iter().any(|id| id == plugin_id))
                .map(|(preset, _)| preset),
        );
    }
    out
}

/// The parts of a CLAP preset id: location kind, location (none for one
/// inside the plugin), load key (none when there is none).
pub fn clap_preset_parts(id: &str) -> Result<(u32, Option<CString>, Option<CString>)> {
    // A file named by a script: `file:<path>`.
    if let Some(path) = id.strip_prefix("file:").filter(|p| !p.is_empty()) {
        return Ok((CLAP_PRESET_DISCOVERY_LOCATION_FILE, Some(CString::new(path)?), None));
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
    if kind == CLAP_PRESET_DISCOVERY_LOCATION_FILE && location.is_empty() {
        bail!("not a preset of this plugin");
    }
    Ok((kind, c(location)?, c(key)?))
}

// --- VST3 ---------------------------------------------------------------------

/// Where `.vstpreset` files are kept for a plugin, as the VST3 SDK sets out
/// for Linux: `~/.vst3/presets/<vendor>/<plugin>`, then the system's, then
/// `$VST3_PRESET_PATH` (directories separated by `:`, each laid out the same
/// way), and presets shipped inside the plugin's bundle.
pub fn vst3_preset_dirs(vendor: &str, plugin: &str, bundle: Option<&Path>) -> Vec<PathBuf> {
    let mut roots: Vec<PathBuf> = Vec::new();
    if let Some(extra) = std::env::var_os("VST3_PRESET_PATH") {
        roots.extend(std::env::split_paths(&extra));
    }
    if let Some(home) = std::env::var_os("HOME") {
        roots.push(PathBuf::from(home).join(".vst3/presets"));
    }
    roots.push("/usr/share/vst3/presets".into());
    roots.push("/usr/local/share/vst3/presets".into());
    let mut dirs: Vec<PathBuf> = roots
        .into_iter()
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
    let list_at = i64::from_le_bytes(bytes[40..48].try_into().unwrap()) as usize;
    let list = bytes.get(list_at..).ok_or_else(short)?;
    if list.len() < 8 || &list[..4] != b"List" {
        return Err(short());
    }
    let count = i32::from_le_bytes(list[4..8].try_into().unwrap()).max(0) as usize;
    let (mut comp, mut cont) = (Vec::new(), Vec::new());
    for i in 0..count {
        let entry = list.get(8 + i * 20..8 + (i + 1) * 20).ok_or_else(short)?;
        let offset = i64::from_le_bytes(entry[4..12].try_into().unwrap()) as usize;
        let size = i64::from_le_bytes(entry[12..20].try_into().unwrap()) as usize;
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
        let (kind, location, key) = clap_preset_parts("0\u{1f}/a/b.fxp\u{1f}").unwrap();
        assert_eq!(kind, CLAP_PRESET_DISCOVERY_LOCATION_FILE);
        assert_eq!(location.unwrap().to_str().unwrap(), "/a/b.fxp");
        assert!(key.is_none());
        assert!(clap_preset_parts("junk").is_err());
    }
}
