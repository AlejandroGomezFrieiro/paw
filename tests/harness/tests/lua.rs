//! The Lua suite: one test for each part (see the crate's lib.rs).
//!
//!   cargo nextest run -p paw-lua-suite --profile lua
//!
//! tests/tools/suite.sh runs it so, and gives the words of `only`.

use std::env;
use std::process::ExitCode;

use libtest_mimic::{Arguments, Failed, Trial};
use paw_lua_suite::{IN_SUITE, Suite};

fn main() -> ExitCode {
    // A paw of the suite that runs the suite again would start paw
    // processes without end.
    if env::var_os(IN_SUITE).is_some() {
        eprintln!("the Lua suite does not start inside a run of the Lua suite ({IN_SUITE} is set)");
        return ExitCode::from(2);
    }
    let mut args = Arguments::from_args();
    // nextest runs each test in a process of its own and keeps to the
    // limits of .config/nextest.toml. Without it (`cargo test`), the parts
    // run one at a time, and not one for each core.
    if env::var_os("NEXTEST_RUN_ID").is_none() {
        args.test_threads = Some(1);
    }
    // The suite has no ignored test: the list of them needs no paw.
    if args.list && args.ignored {
        return libtest_mimic::run(&args, Vec::new()).exit_code();
    }
    let suite = Suite::from_env();
    let parts = match suite.parts() {
        Ok(parts) => parts,
        Err(message) => {
            eprintln!("{message}");
            return ExitCode::FAILURE;
        }
    };
    let trials = parts
        .into_iter()
        .map(|part| {
            let suite = suite.clone();
            Trial::test(part.clone(), move || suite.run(&part).map_err(Failed::from))
        })
        .collect();
    libtest_mimic::run(&args, trials).exit_code()
}
