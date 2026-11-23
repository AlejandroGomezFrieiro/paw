//! The environment of each paw that a test starts: nothing of the machine.
//! A copy of crates/paw-tui/tests/sealed/mod.rs: change both.

use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Give `command` the environment of tests/tools/env.sh, with each folder
/// under `dir`: a scratch home, XDG folders, a runtime folder for its
/// sockets, a scratch `WINEPREFIX`, empty plugin folders, a user name that
/// is not the owner's, and no desktop bus. The owner's ~/.clap and ~/.vst3
/// are never searched: a bundle there can be a yabridge bridge, which starts
/// wine in the owner's prefix.
///
/// A variable that the caller set on `command` before this call stays as
/// the caller set it. A test that loads a plugin can also set its own
/// folder after this call.
pub fn seal<'a>(command: &'a mut Command, dir: &Path) -> &'a mut Command {
    let empty = dir.join("no-plugins");
    let xdg = dir.join("xdg");
    // The runtime folder is `dir` itself: a socket path must fit in 108
    // bytes, and the callers give a short `dir` for their sockets.
    let folders: [(&str, PathBuf); 13] = [
        ("HOME", dir.join("home")),
        ("XDG_CONFIG_HOME", xdg.join("config")),
        ("XDG_DATA_HOME", xdg.join("data")),
        ("XDG_STATE_HOME", xdg.join("state")),
        ("XDG_CACHE_HOME", xdg.join("cache")),
        ("XDG_RUNTIME_DIR", dir.to_path_buf()),
        ("WINEPREFIX", dir.join("wine")),
        ("CLAP_PATH", empty.clone()),
        ("LV2_PATH", empty.clone()),
        ("VST3_PATH", empty.clone()),
        ("LADSPA_PATH", empty.clone()),
        ("DSSI_PATH", empty.clone()),
        ("VST3_PRESET_PATH", empty),
    ];
    let values: [(&str, &OsStr); 5] = [
        ("USER", OsStr::new("paw-test")),
        ("LOGNAME", OsStr::new("paw-test")),
        ("DBUS_SESSION_BUS_ADDRESS", OsStr::new("unix:path=/nonexistent/bus")),
        ("GIT_CONFIG_NOSYSTEM", OsStr::new("1")),
        ("PAW_TEST_ENV", OsStr::new("1")),
    ];
    let given: Vec<_> = command
        .get_envs()
        .map(|(name, _)| name.to_os_string())
        .collect();
    let unset = |name: &str| !given.iter().any(|set| set == name);
    for (name, folder) in folders {
        if unset(name) {
            std::fs::create_dir_all(&folder).expect("a scratch folder of the test");
            command.env(name, folder);
        }
    }
    for (name, value) in values {
        if unset(name) {
            command.env(name, value);
        }
    }
    command
}
