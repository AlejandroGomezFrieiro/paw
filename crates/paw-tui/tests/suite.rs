//! Runs the Lua end-to-end suite against the built binary.

mod sealed;

use std::path::Path;
use std::process::Command;

#[test]
fn lua_suite() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut command = Command::new(env!("CARGO_BIN_EXE_paw"));
    command.arg("--clean").current_dir(&root);
    command.env("XDG_CACHE_HOME", env!("CARGO_TARGET_TMPDIR"));
    // Recordings of a project that was never saved go to the data directory.
    command.env("XDG_DATA_HOME", env!("CARGO_TARGET_TMPDIR"));
    // And what the program keeps between runs, to the state directory.
    command.env("XDG_STATE_HOME", env!("CARGO_TARGET_TMPDIR"));
    sealed::seal(&mut command, Path::new(env!("CARGO_TARGET_TMPDIR")));
    // The plugin tests need known plugins. `PAW_TEST_PLUGINS` lists directories
    // that hold `clap`, `lv2` and `vst3` directories; the dev shell sets it.
    // Without it no plugins are loaded, least of all whatever is installed.
    match std::env::var("PAW_TEST_PLUGINS") {
        Ok(dirs) => {
            for (variable, format) in [
                ("CLAP_PATH", "clap"),
                ("LV2_PATH", "lv2"),
                ("VST3_PATH", "vst3"),
            ] {
                let paths: Vec<String> = dirs
                    .split(':')
                    .map(|dir| format!("{dir}/{format}"))
                    .collect();
                command.env(variable, paths.join(":"));
            }
        }
        Err(_) => {
            command.arg("--no-plugins");
        }
    }
    let output = command
        .args(["-l", "tests/suite.lua"])
        .output()
        .expect("failed to run paw");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        output.status.success(),
        "suite failed:\n{stdout}\n{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        stdout.contains("all passed"),
        "suite did not finish:\n{stdout}"
    );
}
