//! Opening a plugin's shared library where the system's libraries are not
//! where the loader looks.
//!
//! A plugin built elsewhere names the libraries it needs (`libfreetype.so.6`,
//! `libcurl.so.4`) and expects the loader to find them. On NixOS nothing is
//! on the loader's default path, and this program's own search path only
//! covers what it was built against. So when a library is missing, it is
//! looked for in the places a system keeps libraries for programs that were
//! not built for it, loaded from there, and the plugin tried again.

use std::path::{Path, PathBuf};
use std::sync::Once;

use anyhow::{Result, anyhow};
use libloading::os::unix::{Library, RTLD_LAZY, RTLD_LOCAL};

/// What the loader says when a needed library is not found.
const MISSING: &str = ": cannot open shared object file";

/// Libraries that plugins open by name while they run, rather than name as
/// needed: a window toolkit looks for the display's libraries this way.
/// Loading them ahead means those lookups succeed.
const OPENED_LATER: &[&str] = &[
    "libX11.so.6",
    "libXext.so.6",
    "libXrender.so.1",
    "libXrandr.so.2",
    "libXinerama.so.1",
    "libXcursor.so.1",
    "libXcomposite.so.1",
    "libxcb.so.1",
    "libGL.so.1",
    "libasound.so.2",
    "libfontconfig.so.1",
    "libfreetype.so.6",
];

/// Where the build environment kept the libraries plugins look for, when it
/// said (`PAW_PLUGIN_LIB_DIRS`, set by the dev shell on a system that has
/// them nowhere else).
const BUILT_WITH: Option<&str> = option_env!("PAW_PLUGIN_LIB_DIRS");

/// Where to look for a library the loader did not find: `PAW_PLUGIN_LIBS`
/// (directories separated by colons) first, then where nix-ld and the
/// system profiles keep them, then where the build found them, then the
/// usual places of other systems.
pub fn search_dirs() -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = Vec::new();
    for variable in ["PAW_PLUGIN_LIBS", "NIX_LD_LIBRARY_PATH"] {
        if let Some(list) = std::env::var_os(variable) {
            dirs.extend(std::env::split_paths(&list));
        }
    }
    dirs.extend(std::env::split_paths(BUILT_WITH.unwrap_or_default()));
    dirs.push("/run/current-system/sw/share/nix-ld/lib".into());
    dirs.push("/run/current-system/sw/lib".into());
    if let Some(home) = std::env::var_os("HOME") {
        dirs.push(Path::new(&home).join(".nix-profile/lib"));
    }
    if let Some(user) = std::env::var_os("USER") {
        dirs.push(Path::new("/etc/profiles/per-user").join(user).join("lib"));
    }
    for dir in [
        "/usr/lib/x86_64-linux-gnu",
        "/usr/lib64",
        "/usr/lib",
        "/lib64",
    ] {
        dirs.push(dir.into());
    }
    dirs.retain(|dir| dir.is_dir());
    dirs
}

/// The library a loader error says is missing, if that is what it says.
fn missing(message: &str) -> Option<&str> {
    let end = message.find(MISSING)?;
    let name = message[..end].rsplit(": ").next()?.trim();
    (!name.is_empty() && !name.contains('/')).then_some(name)
}

/// Load a library found in one of the search directories, and whatever it
/// needs in turn. It stays loaded: the plugins that need it are never
/// unloaded either.
fn preload(name: &str, depth: usize) -> bool {
    for dir in search_dirs() {
        let candidate = dir.join(name);
        if candidate.exists() && open_at(&candidate, depth + 1).is_ok() {
            return true;
        }
    }
    false
}

fn open_at(path: &Path, depth: usize) -> Result<()> {
    let library = open_with(path, depth)?;
    std::mem::forget(library);
    Ok(())
}

fn open_with(path: &Path, depth: usize) -> Result<Library> {
    let mut given_up: Vec<String> = Vec::new();
    loop {
        // SAFETY: Loading a library runs its initializers; paw loads only plugin libraries it was asked
        // to open, and the path is a valid file path. The same trust as any plugin load.
        let err = match unsafe { Library::open(Some(path), RTLD_LAZY | RTLD_LOCAL) } {
            Ok(library) => return Ok(library),
            Err(err) => err.to_string(),
        };
        // Bounded: a library is looked for once, and chains are short.
        match missing(&err) {
            Some(name)
                if depth < 8 && !given_up.iter().any(|n| n == name) && given_up.len() < 64 =>
            {
                if !preload(name, depth) {
                    return Err(anyhow!(
                        "{err} (looked for {name} in {} too; set PAW_PLUGIN_LIBS to where it is)",
                        search_dirs()
                            .iter()
                            .map(|d| d.display().to_string())
                            .collect::<Vec<_>>()
                            .join(", ")
                    ));
                }
                given_up.push(name.to_string());
            }
            _ => return Err(anyhow!("{err}")),
        }
    }
}

/// Open a plugin's shared library, finding the libraries it needs where the
/// loader alone would not.
pub fn open_library(path: &Path) -> Result<Library> {
    // Have ready what a plugin will look for by name once it runs. Every
    // plugin, not only one whose own needs were missing: a plugin that names
    // nothing as needed still opens the display's libraries for its editor,
    // and without them the editor's window stays empty.
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        for name in OPENED_LATER {
            // SAFETY: Loading a library the plugin would look for by name runs its initializers, the same
            // trust as loading the plugin; the handle is forgotten so the library stays loaded.
            let found = unsafe {
                Library::open(Some(name), RTLD_LAZY | RTLD_LOCAL)
                    .map(std::mem::forget)
                    .is_ok()
            };
            if !found {
                preload(name, 0);
            }
        }
    });
    // SAFETY: Loading a library runs its initializers; this is the plugin load the user asked for.
    match unsafe { Library::open(Some(path), RTLD_LAZY | RTLD_LOCAL) } {
        Ok(library) => Ok(library),
        Err(err) if missing(&err.to_string()).is_some() => open_with(path, 0),
        Err(err) => Err(anyhow!("{err}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_loader_error_names_the_library_that_is_missing() {
        assert_eq!(
            missing("libfreetype.so.6: cannot open shared object file: No such file or directory"),
            Some("libfreetype.so.6")
        );
        assert_eq!(
            missing("/x/a.so: libcurl.so.4: cannot open shared object file: No such file"),
            Some("libcurl.so.4")
        );
        // The plugin's own file being absent is not a missing dependency.
        assert_eq!(
            missing("/x/a.so: cannot open shared object file: No such file or directory"),
            None
        );
        assert_eq!(missing("undefined symbol: foo"), None);
    }

    #[test]
    fn where_the_build_found_libraries_is_searched() {
        // Nothing to check where the build environment did not say.
        for dir in std::env::split_paths(BUILT_WITH.unwrap_or_default()) {
            if dir.is_dir() {
                assert!(
                    search_dirs().contains(&dir),
                    "{} is searched",
                    dir.display()
                );
            }
        }
    }
}
