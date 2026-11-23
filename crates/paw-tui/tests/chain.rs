//! `paw chain schema`: paw's schema of the chain language, which another
//! tool (a language server, an agent) reads to check a chain of paw.

mod sealed;

use std::path::Path;
use std::process::Command;

#[test]
fn paw_chain_schema_prints_the_schema_of_paw_as_json() {
    let dir = scratch();
    let mut command = Command::new(env!("CARGO_BIN_EXE_paw"));
    sealed::seal(&mut command, &dir).args(["chain", "schema", "--clean", "--no-plugins"]);
    let output = command.output().expect("paw runs");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success(), "paw chain schema fails: {}", String::from_utf8_lossy(&output.stderr));
    let schema = chain_syntax::Schema::from_json(&stdout).expect("the output is a chain schema");
    assert_eq!(schema.host, "paw");
    assert!(schema.device("compressor").is_some(), "a built-in device is in the schema");
    assert!(schema.split("band").is_some(), "a kind of split is in the schema");
    let _ = std::fs::remove_dir_all(&dir);
}

/// A folder of this test's own under the target folder.
fn scratch() -> std::path::PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("chain-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("a scratch folder");
    dir
}
