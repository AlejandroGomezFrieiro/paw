//! Where paw finds the user's base directories and the default control
//! socket.
//!
//! Each function follows the XDG base directory rule: the variable, when it
//! is set and not empty (an empty value counts as unset), else a folder in
//! `$HOME`. It gives `None` when neither exists; the caller chooses the last
//! fallback. This is kept by hand and not taken from the `dirs` crate: that
//! crate has no rule for `XDG_RUNTIME_DIR` in the temporary directory, and
//! each caller here wants its own last fallback, so a crate would add a
//! layer and not remove the few lines.

use std::ffi::OsString;
use std::path::PathBuf;

/// A variable's value, unless it is unset or empty.
fn var(name: &str) -> Option<OsString> {
    std::env::var_os(name).filter(|value| !value.is_empty())
}

/// `$name`, else `$HOME/fallback`.
fn base(name: &str, fallback: &str) -> Option<PathBuf> {
    var(name)
        .map(PathBuf::from)
        .or_else(|| var("HOME").map(|home| PathBuf::from(home).join(fallback)))
}

/// `$XDG_CONFIG_HOME`, else `~/.config`.
pub fn config() -> Option<PathBuf> {
    base("XDG_CONFIG_HOME", ".config")
}

/// `$XDG_DATA_HOME`, else `~/.local/share`.
pub fn data() -> Option<PathBuf> {
    base("XDG_DATA_HOME", ".local/share")
}

/// `$XDG_STATE_HOME`, else `~/.local/state`.
pub fn state() -> Option<PathBuf> {
    base("XDG_STATE_HOME", ".local/state")
}

/// `$XDG_CACHE_HOME`, else `~/.cache`.
pub fn cache() -> Option<PathBuf> {
    base("XDG_CACHE_HOME", ".cache")
}

/// `$XDG_RUNTIME_DIR`. There is no fallback in `$HOME`.
pub fn runtime() -> Option<PathBuf> {
    var("XDG_RUNTIME_DIR").map(PathBuf::from)
}

/// The control socket of a kernel that was not told where to listen:
/// `$XDG_RUNTIME_DIR/paw.sock`, in the temporary directory without the
/// variable. Clients use [`default_socket`].
pub fn listen_socket() -> PathBuf {
    runtime()
        .unwrap_or_else(std::env::temp_dir)
        .join("paw.sock")
}

/// Where `paw` listens unless told otherwise, as its clients find it:
/// `$PAW_SOCKET`, else [`listen_socket`].
pub fn default_socket() -> PathBuf {
    std::env::var_os("PAW_SOCKET").map_or_else(listen_socket, PathBuf::from)
}
