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

/// The library a loader error says is missing, if that is what it says.
fn missing(message: &str) -> Option<&str> {
    let end = message.find(MISSING)?;
    let name = message[..end].rsplit(": ").next()?.trim();
    (!name.is_empty() && !name.contains('/')).then_some(name)
}

/// The folders of `dirs` that exist now, in order: a folder can come after
/// the program starts (a package is installed).
fn existing(dirs: &[PathBuf]) -> impl Iterator<Item = &PathBuf> {
    dirs.iter().filter(|dir| dir.is_dir())
}

/// Load a library found in one of the folders of `dirs`, and whatever it
/// needs in turn. It stays loaded: the plugins that need it are never
/// unloaded either.
fn preload(name: &str, dirs: &[PathBuf], depth: usize) -> bool {
    for dir in existing(dirs) {
        let candidate = dir.join(name);
        if candidate.exists() && open_at(&candidate, dirs, depth + 1).is_ok() {
            return true;
        }
    }
    false
}

fn open_at(path: &Path, dirs: &[PathBuf], depth: usize) -> Result<()> {
    let library = open_with(path, dirs, depth)?;
    std::mem::forget(library);
    Ok(())
}

fn open_with(path: &Path, dirs: &[PathBuf], depth: usize) -> Result<Library> {
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
                if !preload(name, dirs, depth) {
                    return Err(anyhow!(
                        "{err} (looked for {name} in {} too; set PAW_PLUGIN_LIBS to where it is)",
                        existing(dirs)
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
/// loader alone would not: in `dirs` ([`crate::PluginDirs`] gives them).
pub fn open_library(path: &Path, dirs: &[PathBuf]) -> Result<Library> {
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
                preload(name, dirs, 0);
            }
        }
    });
    // SAFETY: Loading a library runs its initializers; this is the plugin load the user asked for.
    match unsafe { Library::open(Some(path), RTLD_LAZY | RTLD_LOCAL) } {
        Ok(library) => Ok(library),
        Err(err) if missing(&err.to_string()).is_some() => open_with(path, dirs, 0),
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
}
