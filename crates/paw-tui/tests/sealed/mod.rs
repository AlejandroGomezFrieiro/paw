//! The environment of each paw that a test starts: nothing of the machine.

use std::path::Path;
use std::process::Command;

/// Give `command` a home under `dir` and empty plugin folders, as
/// tests/tools/env.sh does. The owner's ~/.clap and ~/.vst3 are never
/// searched: a bundle there can be a yabridge bridge, which starts wine in
/// the owner's prefix. A test that loads a plugin sets its own folder after
/// this call.
pub fn seal<'a>(command: &'a mut Command, dir: &Path) -> &'a mut Command {
    let home = dir.join("home");
    let empty = dir.join("no-plugins");
    std::fs::create_dir_all(&home).expect("the scratch home");
    std::fs::create_dir_all(&empty).expect("the empty plugin folder");
    command
        .env("HOME", &home)
        .env("WINEPREFIX", dir.join("wine"));
    for variable in [
        "CLAP_PATH",
        "LV2_PATH",
        "VST3_PATH",
        "LADSPA_PATH",
        "DSSI_PATH",
    ] {
        command.env(variable, &empty);
    }
    command.env("PAW_TEST_ENV", "1")
}
