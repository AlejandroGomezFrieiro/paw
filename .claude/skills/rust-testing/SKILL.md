---
name: rust-testing
description: "How to write and change Rust tests in paw: the seam to test at, where a test goes, golden files, property tests, null tests of the engine, the check for no allocation, test doubles without a mock library, error paths, self-contained tests that read nothing of the machine, and what a test must not do. Use it for each Rust change that adds or changes a test, and for each review of Rust tests."
---

# Rust tests in paw

Use this skill for each Rust change that adds or changes a test. It adds
to part 3 of `paw-code` and to the rules for tests in `rust-skills`. The
skill `prune-tests` tells which tests to delete. For the Lua tests, use
`lua-testing`.

Two designs in `backlog/docs/designs/` are the source of this skill.
One is the review of the test suite (the rules for time). The other is
the research on the practices of other projects. The milestone m-12
builds the parts that are marked "planned" here. Do not use a planned part before its ticket is done.

## 1. Choose the seam first

A test crosses the same seam as a caller. Choose the lowest seam that
shows the behavior:

| The change | The test |
| --- | --- |
| A pure function or a model type | A unit test in a `#[cfg(test)] mod tests` of the module |
| The engine (devices, clips, the mix) | An integration test in `crates/paw-engine/tests` that makes an `Engine` and calls `engine.process()` block by block |
| The kernel through Lua (commands, keys, views) | A Lua test, not Rust (`lua-testing`) |
| The remote protocol | `crates/paw-tui/tests/remote.rs` or `crates/paw-mcp/tests/protocol.rs` |
| The terminal input (escape sequences) | `crates/paw-tui/tests/join.rs` |
| The window | Paused: do not write, build or run window tests (see part 9) |

The engine tests are the model: they make an `Engine`, send messages
through its `EngineHandle`, and run blocks. No real-time thread runs and
no real time passes.

- Test the code that paw owns. Do not test the behavior of `std`, of a
  crate or of LuaJIT. A test of glue code is necessary only when the
  glue has its own logic.
- Keep the logic out of the transport. A handler of a protocol message
  is a function from a request to a reply, and a test calls it with no
  socket. A test with a socket is for the transport only.

## 2. Where a test lives

- A unit test is in the module that it tests. It can use private items.
- An integration test is in `crates/<crate>/tests`. Each file there is
  a separate binary that links the crate again. Put a new test in a
  file of its area that is there already. Do not add a file for one test.
- One integration-test binary for each crate is the goal
  (`tests/it/main.rs` with a module for each area). `paw-engine` moves
  first (planned, TASK-154). Keep `no_alloc.rs` as its own binary: it
  sets a global allocator for its process.
- A helper that two files use is a module of the test binary, not a
  copy in each file.
- Doc tests are for the examples of a public item. `cargo nextest` does
  not run them: run `cargo test --doc -p <crate>`.

## 3. One check helper for each feature

Write one helper, for example `check(input, expected)`, that calls the
API under test. The tests give data to the helper. A change of a
signature then changes one helper, not a hundred tests. A test
that reads as a table of cases gets a new case in one line.

```rust
fn check(keys: &str, expected: &[Event]) {
    assert_eq!(decode(keys.as_bytes()), expected, "keys {keys:?}");
}
```

- A table of cases is a loop over a `const` array or a `Vec` that
  calls `check`. paw does not use `rstest` or `test-context`: a function
  and a loop do the same with no macro.
- A setup that many tests share is a function that returns a struct of
  the values. Put a `TempDir` in the struct: its `Drop` cleans up, also
  after a panic. Do not write a function that cleans up at the end.
- A value that many tests use (a name, a small project) is a `const` or
  a function in the helper module of the test binary.

## 4. Assertions

- Use `assert_eq!`, `assert!` and `assert_ne!`. Add a message that
  tells what the value is: `assert_eq!(got, want, "the gain of track
  {n}")`.
- paw does not use `googletest`. A new style of assertion is one more
  thing to learn.
- Write an assertion helper only for logic of the domain, for example
  "these two buffers null to -120 dB". Give the helper a name that
  tells the rule, and make it report the first sample that differs.
- Compare a whole value where you can (`assert_eq!` on a struct or a
  `Vec`), not field by field.
- Write the expected value as a literal: `assert_eq!(name, "Bass 2")`.
  Do not compute it with the logic under test. Then a bug in that logic
  cannot also be in the expected value.
- The name of a test tells the behavior:
  `undo_of_a_split_gives_one_clip`, not `split_2`. The body has three
  parts in this order: arrange, act, assert.

## 5. Golden files with `insta`

Use a golden file for a text output that is longer than about five
lines. `insta` is a dev-dependency of the workspace (features `json`
and `filters`). These golden files exist, and a new one follows them:

| Format | Test | Crate |
| --- | --- | --- |
| A scene, one node of each kind, as the wire has it | `a_new_window_sends_each_kind_of_node_as_the_golden_file_has_it` | `paw-scene` |
| The client's side of the control protocol, with a kernel in memory | `the_client_speaks_the_protocol_as_the_golden_file_has_it` | `paw-proto` |
| A `.midi2` clip: its text and its packets | `a_clip_file_has_the_packets_of_the_golden_file` | `paw-core` (`clipfile.rs`) |
| A project folder on the disk | `a_project_folder_has_the_files_of_the_golden_file` | `paw-core` (`session/folder.rs`) |
| The undo folder | `an_undo_folder_has_the_files_of_the_golden_file` | `paw-core` (`undofile.rs`) |

- Use the most specific macro: `assert_snapshot!` for text,
  `assert_debug_snapshot!` for a `Debug` value, `assert_json_snapshot!`
  for a value that `serde` writes. Write a small function that puts
  one node, packet or message on each line of the text, for the diff.
- An inline snapshot (`assert_snapshot!(x, @"...")`) is for short
  output. A file in `snapshots/` next to the test is for long output.
- A folder on the disk: write it under a `TempDir`, and snapshot
  `crate::golden::folder_text(dir)` (`paw-core`, test builds only). It
  gives each file with its path in the folder, and a `.midi2` clip as
  `paw clip cat` shows it.
- Hide each value that changes from run to run: paths, times, ids from
  a counter or a random source. Use `insta::Settings` with `add_filter`.
  `crate::golden::settings(dir)` replaces the path of `dir` with `[dir]`
  and shortens each BLAKE3 hash to eight digits:

```rust
crate::golden::settings(dir.path()).bind(|| {
    insta::assert_snapshot!(crate::golden::folder_text(dir.path()));
});
```

- A value that the test gives (a fixed nonce, a fixed time) need not be
  hidden. Give the code such a value as an argument, and do not read the
  clock in the test.
- To make or accept snapshots, run `cargo insta test -p <crate>` and
  then `cargo insta review`, and read each diff. Name the accepted
  snapshots in the commit message. A review of the diff is the test.
  Never accept with `INSTA_FORCE_PASS` or with a blind
  `cargo insta accept`.
- The flake's `tests` check sets `INSTA_UPDATE=no`, so a new or changed
  snapshot that is not committed fails.
- The terminal screen has golden files on the Lua side:
  `T.expect_screen` in `tests/screens/`, accepted with
  `PAW_BLESS=1 tests/tools/suite.sh only "<words>"` (skill `lua-testing`,
  part 7). Do not test the layout of a view with `insta`.

## 6. Property tests with `proptest` (planned, TASK-156)

Use a property test for a rule that is true for each input:

- A round trip: decode of encode gives the input, load of save gives
  the project.
- An inverse: an undo of a change gives the old state.
- An equivalence: two ways to compute one value give the same value.

Rules:

- Write one strategy for each type of input, and keep it next to the
  type's tests.
- Commit the files in `proptest-regressions/`. The crate runs each saved
  case first.
- Use the default count of cases in the normal run. The nightly tier in
  CI sets `PROPTEST_CASES`.
- A failure that a property test finds becomes a normal example test too, with
  a name that tells the bug.

## 7. Sound

- **The audio thread.** The engine thread has no lock, no allocation
  and no wait. A new message, device or path of the engine gets a case
  in `crates/paw-engine/tests/no_alloc.rs`. Do not use the crate
  `assert_no_alloc`: paw's own allocator marks the workers of the pool
  for good.
- **Null tests (planned, TASK-153).** Where two ways to render must give
  the same sound, render both and compare sample by sample. Examples:
  blocks of 64 and of 512 frames; one thread and four; a clip moved and
  moved back; a bypassed device and no device. Use bit-exact equality
  where the code is certain. Else use a stated limit in dB, with the
  reason in a comment.
- Check a level or a frequency of a rendered buffer. Do not read a meter
  of a live engine.

## 8. Fakes, not mocks

- paw does not use `mockall`. A mock with `expect_x().times(n)` couples
  the test to the steps of the code, and a suite of mocks costs much to
  keep.
- At a boundary with the outside (a process, a socket, a device, a
  clock), make a small trait with two adapters: the real one and a fake
  that the test controls. Examples: the planned `Clock` trait with
  `WallClock` and `ManualClock` (TASK-146), the `test` and `null` audio
  backends, the stub plugin `examples/stub_clap`.
- One adapter is a seam on paper. Add the trait only when the fake is
  the second adapter.
- Prefer static dispatch (a generic parameter) in hot code, and
  `dyn Trait` where the choice comes at the start of the program.

The kinds of double. Write each one by hand, in the test module or the
helper module:

| Kind | What it does | Example in paw |
| --- | --- | --- |
| Placeholder | Fills an argument that the path under test does not use | A unit struct with empty methods |
| Stub | Gives a fixed answer | A field `answer` that the method returns |
| Spy | Records the calls, for the assertions after the act | A `Vec` of the messages that it got |
| Fake | Does the real work in a short way, in memory | `ManualClock`, the `test` audio backend, the stub plugin |

- Give the double through an argument or a constructor
  (`fn run(sink: &mut impl Sink)`, `Engine::with_clock(clock)`). Do
  not swap a type with `#[cfg(test)] use`: the test then checks a build
  that the user does not run. Do not control a double through a
  `thread_local!` or a `static`.
- Lend the double to the code (`&` or `&mut`). Then the test reads the
  spy after the act. Use `Cell` or `RefCell` only when the method of the
  trait takes `&self`. Do not put assertions in a `Drop` of a double: a
  panic in a drop during a panic aborts the test binary.
- Prefer a check of the result (a fake) to a check of the calls (a spy).
  A spy is for an effect that has no result to read, for example a
  message to a plugin.
- Use a type of `std` before you write a double. `&[u8]` and
  `Cursor<Vec<u8>>` implement `Read` and `BufRead`. `Vec<u8>` implements
  `Write`. So a parser takes `impl BufRead` and a writer takes
  `&mut impl Write`, not a path:

```rust
#[derive(Default)]
struct Sent(Vec<Message>);
impl Sink for Sent {
    fn send(&mut self, message: Message) { self.0.push(message); }
}

#[test]
fn a_stop_sends_all_notes_off() {
    let mut sent = Sent::default();
    stop(&mut sent);
    assert_eq!(sent.0, [Message::AllNotesOff]);
}
```

- Code that must use a real folder (a project folder, a rename, a
  watch) uses a `TempDir`, not a double of the file system.

## 9. Isolation

Each test acts as if it is the only test that runs.

- Files: write under a `tempfile::TempDir` or `NamedTempFile`, which
  delete their files on drop, also after a panic. Give each test its own
  folder.
- Never call `std::env::set_current_dir` or `std::env::set_var` in a
  test. nextest runs each test in its own process, but `cargo test`
  runs the tests of a binary as threads of one process. Give a path or a
  setting to the code as an argument.
- Code that reads a fixed path is hard to test. Resolve the path in
  `main` and give it to the library.
- A socket or a server binds port 0 or a path under the test's folder.
  A fixed port forces the tests to run one at a time.
- The window is paused (owner, 2026-11-22). paw-gui is not a default
  workspace member. Do not run `cargo test -p paw-gui` and do not add
  tests to `crates/paw-gui` until the owner starts that work again.

## 10. Self-contained

The owner's rule: a test is fully self-contained. It does not depend on
the owner's computer or folders. Mock what it needs.

- A test reads nothing of the machine: not the home folder, not the
  installed plugins (`CLAP_PATH`, `VST3_PATH`, `~/.clap`, `~/.vst3`; a
  yabridge bridge in `~/.vst3` starts wine), not the user name, not the
  system fonts, not the desktop bus, not the network. It does not use
  the owner's display, audio devices or configuration.
- A test that starts paw (or `paw ctl`, or `paw-mcp`) seals the command.
  The helper `crates/<crate>/tests/sealed/mod.rs` gives the environment
  of `tests/tools/env.sh` under the test's folder: a scratch home,
  scratch `XDG_*` folders, the test's folder as `XDG_RUNTIME_DIR` (keep
  it short: a socket path must fit in 108 bytes), a scratch
  `WINEPREFIX`, empty plugin folders, the user name `paw-test`, no system
  configuration of git and no desktop bus. It sets only the variables
  that the caller did not set before the call. A test that loads a
  plugin sets its own folder before or after the seal. Also give
  `--audio null` (or `test`) and `--clean`. paw-tui and paw-mcp each
  have a copy of the helper: change both.

```rust
mod sealed;

let dir = tempfile::tempdir().unwrap();
let mut paw = Command::new(env!("CARGO_BIN_EXE_paw"));
sealed::seal(&mut paw, dir.path()).args(["--clean", "--audio", "null"]);
```

- Library code does not read `HOME`, `USER` or a `*_PATH` variable
  itself. `main` resolves the folders and gives them as an argument. A
  unit test then gives a folder under its `TempDir`. paw-plugins still
  reads `HOME`, `USER` and the plugin path variables itself (TASK-162
  moves them to an argument).
- Mock what is needed: the stub CLAP plugin (`examples/stub_clap`), a
  fake behind a trait, or a scratch folder. Never an installed plugin.
- Run paw by hand only through `tests/tools/run.sh`. It uses the same
  sealed environment as the tests.

## 11. No time and no speed

- A test checks behavior, not speed. No assertion on a `Duration`, an
  `Instant`, a share of a processor, or a count that changes with speed.
  To guard a cost, count the work (renders, compiles, cells drawn). A
  time goes to `bench/`.
- The lint `tools/testlint.lua` counts `thread::sleep`, `Instant::now`,
  `cpu_percent` and `quiet(` with a `Duration` in the Rust tests. A count
  over `tests/timing-allowed.txt` fails the suite and `nix flake check`.
  It also fails on each `var("HOME")`, `var_os("USER")`, `home_dir(`,
  `/etc/passwd` or `"/home/` in the test code. These have no allow-list.
- A test does not sleep: no `std::thread::sleep`, no busy loop, no
  `recv_timeout` as the condition of a pass. Step the code: call
  `engine.process()`, call the `poll` of a scheduler with a time that
  the test gives, or advance the planned `ManualClock`.
- Check that a thing does not happen only after a sync point. First
  send a sync request, or step to quiescence, and advance past each
  timer that could make it happen. Then check. "Nothing came in 400 ms"
  is not a check (the remote barrier is planned, TASK-150).
- A wait for another thread or process is a wait for an event: a
  channel message, an acknowledgment, a handshake. The one limit of
  time is the stall guard of nextest (`slow-timeout` in
  `.config/nextest.toml`).
- A test of `async` code (`#[tokio::test]`) has the same rules. The code takes
  paw's `Clock` (TASK-146), not `tokio::time` directly, so the test
  advances a `ManualClock` and does not sleep.

## 12. Errors

- A fallible input (a file, a message, a plugin) has a test of its
  error: the variant, and the message that the user sees.
- A fix of a panic has a test that panicked on the old code.
- Take the error with `let ... else`, and check the variant with
  `matches!`. Then check the text that the user sees:

```rust
let Err(error) = parse_clip(b"MThd") else { panic!("a short header parsed") };
assert!(matches!(error, ClipError::Truncated { .. }), "{error:?}");
assert_eq!(error.to_string(), "the clip ends in its header");
```

- A test of a success path can return `Result<(), E>` and use `?` for
  its arrange steps, in place of many `unwrap()` calls.
- Use `#[should_panic(expected = "...")]` only for a panic that is the
  contract of a function, for example an index out of range. A failure
  that a user can cause is an `Err`, not a panic.

## 13. Fuzz targets (planned, TASK-159)

A parser of input from outside paw (MIDI files, `.midi2` clips, project
JSON, terminal input, the remote protocol) gets a cargo-fuzz target in
the `fuzz/` crate. The target calls the same `check` helper as the
tests and checks "an error, not a panic". The fuzz crate needs nightly
Rust and is not a default member of the workspace. CI builds it, and the
nightly tier in CI runs it. A crash that the fuzzer finds becomes a
normal regression test in its crate.

## 14. Flakes

- nextest has `retries = 0`. Never add a retry.
- A test that fails once and passes again is a bug. Find the cause:
  time, order, shared state, a global. Do not change a time or a
  tolerance to make it pass.
- If you cannot fix it now, quarantine it: `#[ignore = "quarantine:
  TASK-<n>"]`, a line in `tests/quarantine.txt`, and a ticket. The list
  only gets shorter (TASK-145 adds the runner support).
- Any other `#[ignore]` has a reason that names its ticket.

## 15. Commands

Run them in the dev shell. Agents do not build or run tests when the
orchestrator builds (the rules of the session). Name the tests to run in
the report.

```sh
cargo check -p <crate>                        # no link
cargo clippy -p <crate> --tests               # the tests too
cargo nextest run -p <crate>                  # the edit loop: one crate
cargo nextest run -p <crate> -E 'test(word)'  # some tests
cargo test --doc -p <crate>                   # doc tests
cargo nextest run --workspace --profile gate  # before a push
cargo insta test -p <crate>                   # run the tests, keep new snapshots as .snap.new
cargo insta review                            # read and accept snapshots
PAW_BLESS=1 tests/tools/suite.sh only "<words>"  # accept the golden screens (Lua)
```

## 16. Before you commit

- Apply `prune-tests` to each test that you added or changed.
- Each new test fails when its behavior breaks. Use mutation as a lens:
  would the test fail if `>` became `>=`?
- No test reads the clock, sleeps or checks a time.
- No test reads the home folder, the installed plugins or another thing
  of the machine.
- Each snapshot that you accepted is named in the commit message.
