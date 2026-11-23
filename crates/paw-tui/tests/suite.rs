//! Runs the Lua end-to-end suite against the built binary, through
//! tests/tools/suite.sh: the same runner, folders and passes as a run by
//! hand (one runner path).

mod sealed;

use std::path::Path;
use std::process::Command;

#[test]
fn lua_suite() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let binary = Path::new(env!("CARGO_BIN_EXE_paw"));
    let scratch = Path::new(env!("CARGO_TARGET_TMPDIR")).join("lua-suite");
    let mut command = Command::new("sh");
    command
        .arg("tests/tools/suite.sh")
        .current_dir(&root)
        // The binary that cargo built, not target/release: suite.sh takes
        // the binary's folder.
        .env(
            "PAW_TEST_BIN",
            binary.parent().expect("the folder of the paw binary"),
        )
        // suite.sh's env.sh gives the sealed environment under this folder.
        .env("PAW_TEST_SCRATCH", &scratch);
    sealed::seal(&mut command, &scratch);
    // The plugin tests need known plugins. `PAW_TEST_PLUGINS` lists directories
    // that hold `clap`, `lv2` and `vst3` directories; the dev shell sets it.
    // Without it no plugins are loaded, least of all whatever is installed.
    if std::env::var_os("PAW_TEST_PLUGINS").is_some() {
        command.arg("plugins");
    }
    let output = command.output().expect("failed to run tests/tools/suite.sh");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        output.status.success(),
        "suite failed (the whole output is in {}):\n{stdout}\n{}",
        scratch.join("suite.out").display(),
        String::from_utf8_lossy(&output.stderr)
    );
}
