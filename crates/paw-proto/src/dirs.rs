//! The user's base directories and the default control socket.
//!
//! A program resolves the base directories once at its start
//! ([`Dirs::from_vars`]) and gives them to the parts that name files in them.
//! Library code does not read `HOME` or `XDG_*` itself, so that a test gives
//! its own folders as a value.
//!
//! Each directory follows the XDG base directory rule: the variable, when it
//! is set and not empty (an empty value counts as unset), else a folder in
//! `$HOME`. It is `None` when neither exists; the caller chooses the last
//! fallback. This is kept by hand and not taken from the `dirs` crate: that
//! crate reads the environment itself, has no rule for `XDG_RUNTIME_DIR` in
//! the temporary directory, and each caller here wants its own last fallback.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

/// The user's base directories, as the program found them at its start.
/// `Dirs::default()` has none: each caller then uses its last fallback, the
/// temporary directory for most.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Dirs {
    /// `$XDG_CONFIG_HOME`, else `~/.config`.
    pub config: Option<PathBuf>,
    /// `$XDG_DATA_HOME`, else `~/.local/share`.
    pub data: Option<PathBuf>,
    /// `$XDG_STATE_HOME`, else `~/.local/state`.
    pub state: Option<PathBuf>,
    /// `$XDG_CACHE_HOME`, else `~/.cache`.
    pub cache: Option<PathBuf>,
    /// `$XDG_RUNTIME_DIR`. There is no fallback in `$HOME`.
    pub runtime: Option<PathBuf>,
}

impl Dirs {
    /// The directories from the variables that `var` gives: the program
    /// gives `std::env::var_os`, a test gives its own.
    pub fn from_vars(var: impl Fn(&str) -> Option<OsString>) -> Self {
        // An empty value counts as unset.
        let var = |name: &str| {
            var(name)
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
        };
        let home = var("HOME");
        let base = |name: &str, fallback: &str| {
            var(name).or_else(|| home.as_ref().map(|home| home.join(fallback)))
        };
        Self {
            config: base("XDG_CONFIG_HOME", ".config"),
            data: base("XDG_DATA_HOME", ".local/share"),
            state: base("XDG_STATE_HOME", ".local/state"),
            cache: base("XDG_CACHE_HOME", ".cache"),
            runtime: var("XDG_RUNTIME_DIR"),
        }
    }

    /// paw's folder in the data directory, in the temporary directory
    /// without one.
    pub fn paw_data(&self) -> PathBuf {
        paw_folder(self.data.as_deref())
    }

    /// paw's folder in the state directory: what this program learns on this
    /// machine. In the temporary directory without one.
    pub fn paw_state(&self) -> PathBuf {
        paw_folder(self.state.as_deref())
    }

    /// paw's folder in the cache directory, in the temporary directory
    /// without one.
    pub fn paw_cache(&self) -> PathBuf {
        paw_folder(self.cache.as_deref())
    }

    /// The control socket of a kernel that was not told where to listen:
    /// `$XDG_RUNTIME_DIR/paw.sock`, in the temporary directory without the
    /// variable.
    pub fn listen_socket(&self) -> PathBuf {
        self.runtime
            .clone()
            .unwrap_or_else(std::env::temp_dir)
            .join("paw.sock")
    }
}

/// `base/paw`, with the temporary directory for a missing `base`.
fn paw_folder(base: Option<&Path>) -> PathBuf {
    base.map_or_else(std::env::temp_dir, Path::to_path_buf)
        .join("paw")
}

/// `$XDG_RUNTIME_DIR`, read from the environment now. Only the window
/// (`paw-gui`, paused) calls it; a new caller takes [`Dirs::runtime`] from
/// its program's start.
pub fn runtime() -> Option<PathBuf> {
    Dirs::from_vars(|name| std::env::var_os(name)).runtime
}

#[cfg(test)]
mod tests {
    use super::*;

    fn check(vars: &[(&str, &str)], expected: Dirs) {
        let found = Dirs::from_vars(|name| {
            vars.iter()
                .find(|(key, _)| *key == name)
                .map(|(_, value)| OsString::from(value))
        });
        assert_eq!(found, expected, "the variables {vars:?}");
    }

    #[test]
    fn a_variable_wins_over_home_and_an_empty_one_counts_as_unset() {
        check(
            &[
                ("HOME", "/h"),
                ("XDG_CONFIG_HOME", "/c"),
                ("XDG_DATA_HOME", ""),
                ("XDG_RUNTIME_DIR", "/r"),
            ],
            Dirs {
                config: Some("/c".into()),
                data: Some("/h/.local/share".into()),
                state: Some("/h/.local/state".into()),
                cache: Some("/h/.cache".into()),
                runtime: Some("/r".into()),
            },
        );
    }

    #[test]
    fn without_home_or_variables_there_are_no_directories() {
        check(&[("HOME", "")], Dirs::default());
    }
}
