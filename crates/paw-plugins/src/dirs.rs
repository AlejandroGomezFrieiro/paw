//! The folders where plugins, the libraries that they need and their
//! presets are looked for.
//!
//! The program resolves the usual folders once at its start, from its
//! environment ([`PluginDirs::from_env`]), and gives the value to the scan.
//! The library code does not read `HOME`, `USER` or a `*_PATH` variable
//! itself. A test makes a value with folders under a temporary folder.

use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::sync::Arc;

/// The variable that gives a plugin's helper the folders added in the
/// program that started it: the helper must find the plugin where the
/// program did.
pub(crate) const ADDED_DIRS_ENV: &str = "PAW_PLUGIN_DIRS";

/// Where the build environment kept the libraries that plugins look for,
/// when it said (`PAW_PLUGIN_LIB_DIRS`, set by the dev shell on a system
/// that has them nowhere else).
const BUILT_WITH: Option<&str> = option_env!("PAW_PLUGIN_LIB_DIRS");

/// The prefixes of the system, after the folders of the user, where each
/// format is in `<prefix>/<format>`.
const SYSTEM_PREFIXES: [&str; 3] = ["/run/current-system/sw/lib", "/usr/local/lib", "/usr/lib"];

/// The usual places of other systems for a library that a plugin needs.
const SYSTEM_LIBRARIES: [&str; 4] = [
    "/usr/lib/x86_64-linux-gnu",
    "/usr/lib64",
    "/usr/lib",
    "/lib64",
];

/// The folders to search, in order. The first folder that has a plugin
/// wins where a format registers one plugin for each id.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PluginDirs {
    /// The usual folders of each format: the format's variable when it is
    /// set, else the folders of the user and of the system.
    pub clap: Vec<PathBuf>,
    pub vst3: Vec<PathBuf>,
    pub lv2: Vec<PathBuf>,
    /// Where a library that a plugin needs is looked for when the loader
    /// does not find it ([`crate::libs`]). Folders that do not exist are
    /// in the list too: [`crate::libs`] skips them when it searches.
    pub libraries: Arc<[PathBuf]>,
    /// The roots of the `.vstpreset` files, each with the layout
    /// `<root>/<vendor>/<plugin>` ([`crate::presets::vst3_preset_dirs`]).
    pub vst3_presets: Arc<[PathBuf]>,
    /// The folders added in this session ([`crate::add_dir`]), in the order
    /// of the adds, with no folder two times. They are searched for CLAP,
    /// VST3 and LV2 plugins after the usual folders. [`PluginDirs::add`]
    /// and [`PluginDirs::remove`] change it.
    pub(crate) added: Vec<PathBuf>,
}

impl PluginDirs {
    /// The usual folders on this machine, with `var` as the environment:
    /// the program gives `std::env::var_os`.
    pub fn from_env(var: impl Fn(&str) -> Option<OsString>) -> Self {
        let home = var("HOME").map(PathBuf::from);
        let user = var("USER");
        let format = |variable: &str, name: &str| {
            format_dirs(
                var(variable).as_deref(),
                home.as_deref(),
                user.as_deref(),
                name,
            )
        };
        Self {
            clap: format("CLAP_PATH", "clap"),
            vst3: format("VST3_PATH", "vst3"),
            lv2: format("LV2_PATH", "lv2"),
            libraries: library_dirs(&var, home.as_deref(), user.as_deref()).into(),
            vst3_presets: vst3_preset_roots(var("VST3_PRESET_PATH").as_deref(), home.as_deref())
                .into(),
            added: Vec::new(),
        }
    }

    /// As [`PluginDirs::from_env`], for a plugin's helper: with the
    /// folders that the program that started it added.
    pub fn for_helper(var: impl Fn(&str) -> Option<OsString>) -> Self {
        let handed = var(ADDED_DIRS_ENV);
        let mut dirs = Self::from_env(var);
        if let Some(handed) = handed {
            for dir in std::env::split_paths(&handed) {
                dirs.add(&dir);
            }
        }
        dirs
    }

    /// Search `dir` too, after the folders that are there. Returns whether
    /// it was new.
    pub fn add(&mut self, dir: &Path) -> bool {
        if self.added.iter().any(|known| known == dir) {
            return false;
        }
        self.added.push(dir.to_path_buf());
        true
    }

    /// Search `dir` no more, when it was added.
    pub fn remove(&mut self, dir: &Path) {
        self.added.retain(|known| known != dir);
    }

    /// The folders added, as [`ADDED_DIRS_ENV`] gives them to a helper.
    /// `None` when there are none.
    pub(crate) fn added_for_helper(&self) -> Option<OsString> {
        if self.added.is_empty() {
            return None;
        }
        std::env::join_paths(&self.added).ok()
    }

    /// The folders to search for one format: its usual folders, then the
    /// folders added.
    pub(crate) fn search(&self, usual: &[PathBuf]) -> Vec<PathBuf> {
        usual.iter().chain(&self.added).cloned().collect()
    }

    /// The folders searched for each format, by the name of the format, as
    /// [`paw_engine::Registry::plugin_dirs`] gives them.
    pub fn by_format(&self) -> Vec<(String, Vec<PathBuf>)> {
        [
            ("clap", &self.clap),
            ("lv2", &self.lv2),
            ("vst3", &self.vst3),
        ]
        .into_iter()
        .map(|(name, usual)| (name.to_string(), self.search(usual)))
        .collect()
    }
}

/// The usual folders of one format: the format's variable (folders
/// separated by `:`) when it is set, else `~/.<name>`, the Nix profiles of
/// the user and the prefixes of the system.
fn format_dirs(
    variable: Option<&OsStr>,
    home: Option<&Path>,
    user: Option<&OsStr>,
    name: &str,
) -> Vec<PathBuf> {
    if let Some(paths) = variable {
        return std::env::split_paths(paths).collect();
    }
    let mut dirs = Vec::new();
    if let Some(home) = home {
        dirs.push(home.join(format!(".{name}")));
        dirs.push(home.join(format!(".nix-profile/lib/{name}")));
    }
    if let Some(user) = user {
        dirs.push(
            Path::new("/etc/profiles/per-user")
                .join(user)
                .join("lib")
                .join(name),
        );
    }
    dirs.extend(
        SYSTEM_PREFIXES
            .iter()
            .map(|prefix| Path::new(prefix).join(name)),
    );
    dirs
}

/// Where to look for a library that the loader did not find:
/// `PAW_PLUGIN_LIBS` (folders separated by `:`) first, then
/// `NIX_LD_LIBRARY_PATH`, then where the build found them, then where
/// nix-ld and the profiles keep them, then the usual places of other
/// systems.
fn library_dirs(
    var: &impl Fn(&str) -> Option<OsString>,
    home: Option<&Path>,
    user: Option<&OsStr>,
) -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = Vec::new();
    for variable in ["PAW_PLUGIN_LIBS", "NIX_LD_LIBRARY_PATH"] {
        if let Some(list) = var(variable) {
            dirs.extend(std::env::split_paths(&list));
        }
    }
    dirs.extend(std::env::split_paths(BUILT_WITH.unwrap_or_default()));
    dirs.push("/run/current-system/sw/share/nix-ld/lib".into());
    dirs.push("/run/current-system/sw/lib".into());
    if let Some(home) = home {
        dirs.push(home.join(".nix-profile/lib"));
    }
    if let Some(user) = user {
        dirs.push(Path::new("/etc/profiles/per-user").join(user).join("lib"));
    }
    dirs.extend(SYSTEM_LIBRARIES.iter().map(PathBuf::from));
    dirs
}

/// The roots of the VST3 presets: `$VST3_PRESET_PATH` (folders separated by
/// `:`), then `~/.vst3/presets`, then the folders of the system.
fn vst3_preset_roots(variable: Option<&OsStr>, home: Option<&Path>) -> Vec<PathBuf> {
    let mut roots: Vec<PathBuf> = Vec::new();
    if let Some(extra) = variable {
        roots.extend(std::env::split_paths(extra));
    }
    if let Some(home) = home {
        roots.push(home.join(".vst3/presets"));
    }
    roots.push("/usr/share/vst3/presets".into());
    roots.push("/usr/local/share/vst3/presets".into());
    roots
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An environment with only the variables in `vars`.
    fn env<'a>(vars: &'a [(&'a str, &'a str)]) -> impl Fn(&str) -> Option<OsString> + 'a {
        move |name| {
            vars.iter()
                .find(|(key, _)| *key == name)
                .map(|(_, value)| OsString::from(value))
        }
    }

    fn paths(list: &[&str]) -> Vec<PathBuf> {
        list.iter().map(PathBuf::from).collect()
    }

    #[test]
    fn the_folders_of_the_user_come_before_the_folders_of_the_system() {
        let dirs = PluginDirs::from_env(env(&[("HOME", "/h"), ("USER", "u")]));
        assert_eq!(
            dirs.clap,
            paths(&[
                "/h/.clap",
                "/h/.nix-profile/lib/clap",
                "/etc/profiles/per-user/u/lib/clap",
                "/run/current-system/sw/lib/clap",
                "/usr/local/lib/clap",
                "/usr/lib/clap",
            ])
        );
        assert_eq!(
            dirs.lv2[0],
            PathBuf::from("/h/.lv2"),
            "each format has its own folders"
        );
        assert_eq!(
            dirs.vst3_presets[..],
            paths(&[
                "/h/.vst3/presets",
                "/usr/share/vst3/presets",
                "/usr/local/share/vst3/presets"
            ])
        );
    }

    #[test]
    fn a_format_variable_replaces_the_usual_folders_of_that_format_only() {
        let dirs = PluginDirs::from_env(env(&[("HOME", "/h"), ("VST3_PATH", "/a:/b")]));
        assert_eq!(dirs.vst3, paths(&["/a", "/b"]));
        assert_eq!(dirs.clap[0], PathBuf::from("/h/.clap"));
    }

    #[test]
    fn with_no_home_and_no_user_only_the_system_is_searched() {
        let dirs = PluginDirs::from_env(env(&[]));
        assert_eq!(
            dirs.vst3,
            paths(&[
                "/run/current-system/sw/lib/vst3",
                "/usr/local/lib/vst3",
                "/usr/lib/vst3"
            ])
        );
    }

    #[test]
    fn the_variables_of_the_libraries_come_first() {
        let dirs = PluginDirs::from_env(env(&[
            ("PAW_PLUGIN_LIBS", "/mine"),
            ("NIX_LD_LIBRARY_PATH", "/nix-ld"),
            ("HOME", "/h"),
        ]));
        assert_eq!(dirs.libraries[..2], paths(&["/mine", "/nix-ld"]));
        assert!(
            dirs.libraries
                .contains(&PathBuf::from("/h/.nix-profile/lib"))
        );
        assert_eq!(dirs.libraries.last(), Some(&PathBuf::from("/lib64")));
    }

    #[test]
    fn where_the_build_found_libraries_is_searched() {
        let dirs = PluginDirs::from_env(env(&[]));
        for dir in std::env::split_paths(BUILT_WITH.unwrap_or_default()) {
            assert!(
                dirs.libraries.contains(&dir),
                "{} is searched",
                dir.display()
            );
        }
    }

    #[test]
    fn an_added_folder_is_searched_after_the_usual_ones_once_until_it_is_removed() {
        let mut dirs = PluginDirs::from_env(env(&[("CLAP_PATH", "/usual")]));
        assert!(dirs.add(Path::new("/ext")));
        assert!(!dirs.add(Path::new("/ext")), "a folder is added one time");
        assert_eq!(dirs.search(&dirs.clap), paths(&["/usual", "/ext"]));
        dirs.remove(Path::new("/ext"));
        assert_eq!(dirs.search(&dirs.clap), paths(&["/usual"]));
        assert_eq!(dirs.added_for_helper(), None);
    }

    #[test]
    fn each_format_tells_its_folders_with_the_added_ones() {
        let mut dirs = PluginDirs::from_env(env(&[
            ("CLAP_PATH", "/c"),
            ("LV2_PATH", "/l"),
            ("VST3_PATH", "/v"),
        ]));
        dirs.add(Path::new("/ext"));
        assert_eq!(
            dirs.by_format(),
            [
                ("clap".to_string(), paths(&["/c", "/ext"])),
                ("lv2".to_string(), paths(&["/l", "/ext"])),
                ("vst3".to_string(), paths(&["/v", "/ext"])),
            ]
        );
    }

    #[test]
    fn a_helper_gets_the_folders_that_its_program_added() {
        let mut program = PluginDirs::from_env(env(&[]));
        program.add(Path::new("/one"));
        program.add(Path::new("/two"));
        let handed = program.added_for_helper().unwrap();
        let handed = handed.to_str().unwrap();
        let helper = PluginDirs::for_helper(env(&[(ADDED_DIRS_ENV, handed)]));
        assert_eq!(helper, program);
    }
}
