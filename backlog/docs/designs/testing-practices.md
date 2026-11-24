# Testing practices: what other projects do, and what paw adopts

Research only. No tracked file changed, no ticket and no skill made.
Written on 2026-11-22 at `e770d109`. Internal text, in Simplified
Technical English.

The present research builds on two earlier documents and does not repeat them:

- [test-suite-review.md](test-suite-review.md): the rules for a test
  (no time, no speed, quiescence, handshakes), the clock seam, the
  stepped audio backend, the lint against time, and the tickets P1 to P8.
- The skill `paw-code` (its part "Tests") and the skill `prune-tests`.

Words that the present research uses with one meaning only:

- **Golden file**: a file in the repository that holds the expected
  output of a test. A person approves each change of it. Other names:
  snapshot, approved file, expect file.
- **Bless**: the step that writes the actual output into the golden
  file (`--bless` in rustc, `cargo insta accept`, `UPDATE_EXPECT=1` in
  rust-analyzer).
- **Property test**: a test that makes many inputs from a seed and
  checks a rule that is true for each input.
- **Fuzz test**: a property test that a coverage-guided engine
  (libFuzzer) drives, for a long time, outside the normal test run.
- **Null test**: an audio test that subtracts two renders and checks
  that the rest is silence (or below a limit).
- **Tier**: a set of checks that run at the same moment: before a
  commit, before a push, each night, or before a release.

## 1. Sources read

The pages were read on 2026-11-22. Where a page was thin, the document
says so, and the claim rests on the project's code or on a second page.

### Rust

- The Rust Book, chapter 11 (tests, unit and integration tests):
  <https://doc.rust-lang.org/book/ch11-00-testing.html>
- Advanced Rust testing (Luca Palmieri, Mainmatter), the whole course:
  <https://rust-exercises.com/advanced-testing/print.html>. Chapters:
  googletest assertions, insta snapshots, mockall, the test system
  (shared state in one binary), tempfile, sqlx databases, wiremock,
  test macros, custom runners with libtest-mimic, a capstone. The course has no
  chapter on time or on async (checked).
- matklad, "How to Test":
  <https://matklad.github.io/2021/05/31/how-to-test.html>
- matklad, "Unit and Integration Tests" (purity and extent):
  <https://matklad.github.io/2022/07/04/unit-and-integration-tests.html>
- matklad, "Delete Cargo Integration Tests":
  <https://matklad.github.io/2021/02/27/delete-cargo-integration-tests.html>
- rust-analyzer architecture, the part "Testing":
  <https://rust-analyzer.github.io/book/contributing/architecture.html>
- rustc dev guide, UI tests:
  <https://rustc-dev-guide.rust-lang.org/tests/ui.html>
- cargo-nextest: process per test
  <https://nexte.st/docs/design/why-process-per-test/>, retries and
  flaky tests <https://nexte.st/docs/features/retries/>, partitions
  <https://nexte.st/docs/ci-features/partitioning/>
- insta: <https://insta.rs/docs/>
- proptest book: <https://proptest-rs.github.io/proptest/>
- Rust Fuzz Book (cargo-fuzz): <https://rust-fuzz.github.io/book/cargo-fuzz.html>
- cargo-mutants: <https://mutants.rs/>, <https://mutants.rs/in-diff.html>
- loom: <https://github.com/tokio-rs/loom>
- shuttle: <https://github.com/awslabs/shuttle>
- Miri: <https://github.com/rust-lang/miri>
- Gungraun (before: iai-callgrind): <https://github.com/gungraun/gungraun>
- cargo-llvm-cov: <https://github.com/taiki-e/cargo-llvm-cov>
- wasmtime fuzzing: <https://docs.wasmtime.dev/contributing-fuzzing.html>
- Zed's test scheduler (`gpui::test`, seeds, `run_until_parked`,
  `advance_clock`): the source of `gpui`
  (<https://docs.rs/crate/gpui/0.2.0/source/src/platform/test/dispatcher.rs>),
  and the Zed blog <https://zed.dev/blog/zed-decoded-async-rust>
  (which only links a talk on property tests of async code).
- Helix integration tests (`test_key_sequence` in
  `helix-term/tests/test/helpers.rs`):
  <https://github.com/helix-editor/helix/tree/master/helix-term/tests>
- TigerBeetle simulation (VOPR):
  <https://docs.tigerbeetle.com/concepts/safety/>

### Audio

- pluginval: <https://github.com/Tracktion/pluginval>
- clap-validator: <https://github.com/free-audio/clap-validator>
- assert_no_alloc: <https://github.com/Windfisch/rust-assert-no-alloc>
- Ardour unit tests (CppUnit, `libs/ardour/test`, `load_session`):
  <https://sources.debian.org/src/ardour/1%3A8.12.0%2Bds-1/doc/unit_tests.txt>
- Audio snapshot tests and tolerances (blog posts, not standards):
  <https://infinum.com/blog/snapshot-testing-for-audio-dsp/>,
  <https://daleonov.github.io/HART/DSPTestingCookbook.html>
- Surge XT's headless Catch2 tests (`src/headless`), seen through a
  mirror of the source. No document about them was found.
- No public document about the tests of Zrythm, LMMS, Bitwig or REAPER
  was found. The document makes no claim about them.

### Lua

- Neovim, the test guide `runtime/doc/dev_test.txt`:
  <https://github.com/neovim/neovim/blob/master/runtime/doc/dev_test.txt>
- Neovim, `test/functional/ui/screen.lua` (the screen tests):
  <https://github.com/neovim/neovim/blob/master/test/functional/ui/screen.lua>
- mini.test: <https://github.com/echasnovski/mini.nvim/blob/main/TESTING.md>
- busted: <https://lunarmodules.github.io/busted/>
- selene: <https://kampfkarren.github.io/selene/motivation.html>
- luacov (through busted's `--coverage`).
- paw's own decision on `tested` (TASK-69) and on luacheck (TASK-70).

### Polyglot, flakes and tiers

- Google Testing Blog, "Where do our flaky tests come from?":
  <https://testing.googleblog.com/2017/04/where-do-our-flaky-tests-come-from.html>,
  and "Flaky tests at Google and how we mitigate them" (2016, about 16 %
  of tests have some flakiness; the text was not reachable, only the
  archive page).
- GitHub, "Reducing flaky builds by 18x":
  <https://github.blog/engineering/infrastructure/reducing-flaky-builds-by-18x/>
- rust-analyzer's rule "all checks are `#[test]`" (the architecture page
  above).
- Neovim's test runner: one `nvim -l` process runs all spec files and puts
  back a baseline before each file (`dev_test.txt`).

### TUI and GUI

- ratatui, snapshot tests with `TestBackend` and insta:
  <https://ratatui.rs/recipes/testing/snapshots/>
- egui_kittest: <https://github.com/emilk/egui/tree/main/crates/egui_kittest>
- Neovim's `screen:expect` and mini.test's `reference_screenshot` (above).

## 2. The practices

Each practice has four parts: what it is, who uses it, the evidence of
value, and the cost.

### 2.1 Rust

**R1. Test features at a boundary, through one `check` function.**

- What: each test calls one helper, `check(input, expected)`. Only that
  helper calls the API under test. A test is data.
- Who: rust-analyzer (`check` in each `ide` module), matklad's essay.
- Evidence: rust-analyzer says that tests that call the API directly
  are "a liability for refactoring". A change of signature touches one
  helper, not a hundred tests. The "neural network test": the tests stay
  valid if the implementation is replaced.
- Cost: low. One helper for each feature.

**R2. Inline fixtures in text.**

- What: the input of a test is a string in a small format: several
  files in one literal, with markers for the cursor (`$0`) and for the
  expected place (`//^^^`).
- Who: rust-analyzer (a goto-definition test runs in about 4 ms in a
  debug build).
- Evidence: no mocks, a test is short, and a failure prints the input.
- Cost: a parser for the fixture format.

**R3. Golden files with a bless step (snapshot or expect tests).**

- What: the test writes its output; a golden file holds the expected
  output; `--bless` (or `cargo insta review`) updates it, and a person
  reviews the diff. Inline snapshots for small values, files for large
  ones. Redactions and filters remove values that change (paths, ids,
  times).
- Who: rustc UI tests (`.stderr` next to each test, `--bless`, paths
  normalized to `$DIR`); rust-analyzer (`expect-test`,
  `UPDATE_EXPECT=1`, parser data in `test_data/`); insta (ratatui,
  many crates); Neovim screen tests; mini.test screenshots.
- Evidence: rustc keeps tens of thousands of UI tests with it. A change
  of output that is correct costs one command, not edits by hand.
  rustc also keeps `//~ ERROR` annotations in the source, because a
  blessed file can bless a mistake.
- Cost: low for text. insta is one dev-dependency. The risk is to bless
  without reading: the review of the diff is the test.

**R4. Property tests.**

- What: a strategy makes inputs from a seed; the test checks a rule;
  a failure is shrunk to a small input and kept in a regression file
  (`proptest-regressions/`), which is committed.
- Who: many crates; matklad recommends exhaustive small inputs (all
  sorted lists up to length 7) as a strong form.
- Evidence: rules such as "decode of encode is the input" and "undo
  after a change gives the old state" find edge cases that examples
  miss.
- Cost: medium. A strategy for each input type. The test is slower than
  an example test, so the number of cases is a setting.

**R5. Coverage-guided fuzzing.**

- What: `cargo fuzz` with libFuzzer, and `arbitrary` for structured
  input. Each crash becomes a regression test.
- Who: wasmtime (fuzz targets with generators and oracles, run all the
  time on OSS-Fuzz, a differential oracle that compares with and
  without optimization), rustc, many parsers.
- Evidence: fuzzers find crashes in parsers of untrusted input that no
  person writes a test for.
- Cost: nightly Rust, a corpus, and machine time. It runs outside the
  normal test run (nightly tier).

**R6. Mutation tests.**

- What: cargo-mutants changes the code (`>` to `>=`, a body to
  `Default::default()`), runs the tests, and reports each mutant that
  no test caught. `--in-diff` limits it to the lines of a diff.
- Who: cargo-mutants users; Google uses mutation tests in code review.
- Evidence: it shows tests that pass whatever the code does. paw-code
  already asks for "mutation as a lens" by hand.
- Cost: high in machine time on a whole workspace (one build and test
  run for each mutant). `--in-diff` makes it a review tool.

**R7. Concurrency checkers: loom, shuttle, Miri.**

- What: loom runs all thread interleavings of a small model under the
  C11 memory model. shuttle runs random interleavings, and scales to
  larger tests, but a pass proves nothing. Miri runs tests in an
  interpreter that finds undefined behavior (out of bounds, use after
  free, data races) in unsafe code.
- Who: tokio (loom), AWS (shuttle), the Rust standard library and many
  `unsafe` crates (Miri).
- Evidence: these tools find bugs that occur once in a million runs.
- Cost: loom and shuttle need the code to use their versions of `sync`
  and `thread` (a `cfg`). Miri does not support most FFI, so it cannot
  run code that calls a plugin, ALSA or LuaJIT.

**R8. One runner per process, no retries, timeouts, groups.**

- What: cargo-nextest runs each test in its own process, kills a test
  that hangs, limits shared resources with test groups, and splits the
  run into shards (`--partition slice:m/n`).
- Who: many large Rust projects. paw already uses it.
- Evidence: a crash or a global in one test does not change another
  test. Retries exist, but a flaky test then counts as a pass by
  default; `--flaky-result fail` makes it a failure.
- Cost: paw has it.

**R9. One integration-test binary per crate.**

- What: `tests/it/main.rs` with the files as modules, in place of one
  binary for each file in `tests/`.
- Who: matklad's essay; Cargo's own test suite (about 3 times faster to
  compile, 5 times less disk).
- Evidence: each file in `tests/` links the whole crate again.
- Cost: low, one move of files. With nextest, the tests still run in
  their own processes.

**R10. Benchmarks apart from tests, and counts in place of time.**

- What: benchmarks with criterion or divan (wall time) or Gungraun
  (instruction counts under Valgrind). Gungraun gives the same number
  on a loaded machine.
- Who: many crates. matklad's "test everything" includes a test of
  linear complexity: timings on inputs of 1, 2, 4, 8 and 16 KB, and a
  check of the slope, not of a time.
- Evidence: instruction counts do not change with load, so they can be
  compared between two commits on a shared machine.
- Cost: Valgrind is slow (each run is 10 to 50 times slower) and does
  not see waits or the cache of a real machine.

**R11. Coverage as a report.**

- What: cargo-llvm-cov measures line, region and (on nightly) branch
  coverage. `show-env` gives the variables that make an external binary
  write coverage. So the paw binary that the Lua suite starts can report
  which Rust code the Lua tests reach.
- Who: many crates, Codecov reports.
- Evidence: coverage shows code that no test reaches. Line coverage does
  not show branches (paw-code, part 6).
- Cost: an instrumented build (slower). A floor (fail under N %) makes
  agents write tests for the number.

**R12. Test the purity first: no IO in the core.**

- What: the core does no IO ("sans IO"); the tests of the core then do
  no IO, and are fast and certain. A few slow tests go through the real
  IO, behind a flag (`RUN_SLOW_TESTS`).
- Who: rust-analyzer (`ide` and `hir` do no IO, so their tests do no
  IO), matklad ("optimize purity, let extent be natural").
- Evidence: rust-analyzer's suite runs in less than 30 s; Cargo's suite
  takes about 7 minutes with `-j 1`.
- Cost: an architecture choice, not a test choice.

**R13. Deterministic simulation.**

- What: the whole program runs on a scheduler and a clock that the test
  owns; a seed decides the order of tasks; a failure prints its seed
  and replays.
- Who: Zed (`gpui::test`, `SEED` and `ITERATIONS`, `run_until_parked`,
  `advance_clock`), TigerBeetle (VOPR, at 1 000 times real speed, with
  faults of the network and the disk), FoundationDB.
- Evidence: races become test failures that replay with one seed.
- Cost: high, unless the program already has one loop and one clock.
  paw's review designs the clock and the step (T3, T4); a seed for the
  order of work is the next step on that seam.

### 2.2 Audio

**A1. Offline render as the test of sound.**

- What: render the project faster than real time, with no device, and
  check the samples.
- Who: every engine with a bounce: Tracktion's tests, Ardour's
  `load_session` helper and its export, Surge XT's headless tests.
- Evidence: the result depends only on the input. paw already does it
  (`paw.render`, 308 uses in 46 files).
- Cost: paw has it.

**A2. Golden renders, with a tolerance that fits the code.**

- What: keep a reference of a render (the samples, a hash, or a short
  print such as the loudness of each second), and compare. Bit-exact
  for code that is certain; a tolerance in dB, or a spectral measure,
  for code that is not (resampling, stretch, plugins).
- Who: DSP libraries (hashes in the repository, a written reason for
  each new reference), paw's end-to-end scenarios (`check_render`, the
  loudness of each second, ±1.5 dB).
- Evidence: one golden render catches a change of sound in any part of
  the chain.
- Cost: a wide tolerance hides real changes; a narrow one breaks on
  each correct change. The bless step and a review of the diff are the
  answer.

**A3. Null tests and invariants of rendering.**

- What: render the same thing two ways that must give the same sound,
  subtract, and check that the rest is silence. Examples: blocks of 64
  and of 512 frames; one thread and four threads; a clip at bar 1 and
  the same clip moved and moved back; render, save, load, render; a
  bypassed device and no device.
- Who: the usual check of DSP engineers ("does it null?"); a common
  property in host tests.
- Evidence: it needs no golden file, so it never needs a bless, and it
  finds errors at the edges of blocks, which are the usual bugs of an
  engine.
- Cost: low. The engine is already certain.

**A4. No allocation and no wait on the audio thread.**

- What: a global allocator that counts allocations on a thread that is
  marked as the audio thread. RealtimeSanitizer (LLVM 20, and the crate
  `rtsan-standalone` for Rust) also finds locks and blocking system
  calls.
- Who: assert_no_alloc (audio crates, nih-plug), pluginval (its higher
  levels), paw (`crates/paw-engine/tests/no_alloc.rs`,
  `crates/paw-plugins/tests/no_alloc.rs`).
- Evidence: an allocation on the audio thread is a dropout that occurs
  rarely and only under load. paw's own guard is better than
  assert_no_alloc for paw: it marks the pool's workers for good
  (the comment in `no_alloc.rs` gives the reason).
- Cost: paw has the allocation part. The lock and system-call part
  (RealtimeSanitizer) is not evaluated yet.

**A5. Validators of the plugin contract.**

- What: pluginval (VST, AU, VST3; strictness 1 to 10; level 5 is "the
  lowest level for host compatibility"; it runs the plugin in another
  process) and clap-validator (CLAP; each test in its own process; a
  fuzzer of parameters, notes and transport, with a seed to replay).
- Who: plugin makers, in CI. They test plugins, not hosts.
- Evidence: they find crashes, wrong threads and wrong state restore in
  plugins.
- Cost: for a host, the value is only for the plugins that the host
  itself makes (paw's stub plugin, and any CLAP device of an
  extension). The host's own side needs the opposite: a plugin that
  breaks the rules on purpose. paw has one (the stub, `sandbox.hang`).

### 2.3 Lua

**L1. A child process that runs the real program.**

- What: each test starts a fresh program (or a fresh state) and drives
  it by RPC: keys in, state and screen out.
- Who: Neovim (`n.clear()` starts a fresh Nvim for each test, 10 to 30
  ms), mini.test (`child.restart`, `child.type_keys`, `child.lua_get`),
  Helix (`test_key_sequence` on a real `Application`).
- Evidence: a test cannot leak state into the next one. Neovim also
  warns when a child takes long to exit (a sign of a leak).
- Cost: a start for each test. paw instead runs all tests in one
  process and resets with `T.fresh()` and the leak check of TASK-121.
  That is Neovim's choice for its runner too ("one `nvim -l` process
  runs all spec files and puts back a baseline before each file"), with
  a child for each test on top.

**L2. Screen tests that compare a whole grid.**

- What: `screen:expect` compares the whole screen with a grid string in
  the test, with attribute ids (`{1:text}`) for the styles. Every
  attribute that the test does not name is an error. On a failure it
  prints the actual screen, ready to paste (`snapshot_util`).
  mini.test keeps reference screenshots (text layer and attribute
  layer) in files, made on the first run, updated with `force`.
- Who: Neovim (thousands of screen tests), mini.nvim.
- Evidence: a test sees each change of what the user sees, also the
  changes that it did not look for. Neovim's `expect` also warns when a
  screen passes at once (the test may pass by accident) and when the
  screen changes after it passed (a race).
- Cost: a grid in a test breaks on each correct change of layout. The
  bless step and small grids (one region, a small size) keep the cost
  low.

**L3. A runner with isolation, shuffle, repeat and tags.**

- What: busted puts back `_G` and `package.loaded` after each file
  (`insulate`), and has `--shuffle`, `--seed`, `--repeat`, tags, and
  TAP or JSON output. Neovim has `TEST_FILTER`, `TEST_TAG`, and
  `--repeat=100 --no-keep-going` to find a flake.
- Who: busted users, Neovim.
- Evidence: shuffle finds order dependence; repeat finds flakes before
  they reach main.
- Cost: low in paw's own runner. paw does not adopt busted or tested
  (TASK-69: they cannot drive the kernel).

**L4. No silent skip.**

- What: a test that cannot run says so (`pending()`, `t.skip()`), so
  the count of tests is the same on each machine.
- Who: Neovim (`dev_test.txt`: "Don't skip silently with if-else").
- Evidence: a silent skip is a test that never runs on CI.
- Cost: none. paw's runner prints `skip` with a reason.

**L5. Static checks as tests.**

- What: lint and type checks run in the same command as the tests.
- Who: rust-analyzer (`#[test]` tests check "all code invariants":
  the format, the tidy checks, the docs); Neovim (EmmyLua check);
  selene and luacheck users.
- Evidence: one command, one result.
- Cost: paw has luacheck (TASK-70), `cyan check` on Teal (the suite
  runs `tools/tlcheck.sh`), the format check, and `apidoc check`.
  selene adds lints, but paw's new code is Teal, which the type checker
  covers.

**L6. Lua coverage.**

- What: luacov counts the lines that ran, with a debug hook.
- Who: busted users.
- Evidence: shows runtime and extension code that no test reaches.
- Cost: the debug hook makes LuaJIT slow and turns off the JIT for the
  hooked code. Teal files are compiled to Lua, so the report is on the
  Lua output, with line numbers that mostly match. Use it as a report,
  not as a gate.

### 2.4 Polyglot: a Rust core with a scripting layer

**P1. A contract test of the API surface.**

- What: a generated list of the API (names, arguments, types, doc
  comments) is in the repository, and a test fails when the code and
  the list disagree.
- Who: Neovim (`api_info()` and the generated `api.txt`, checked in CI);
  paw (`tools/apidoc.lua check`, `tests/apidoc.lua`, Teal declarations
  in `runtime/types`).
- Evidence: a change of the API cannot land without a change of the
  docs and the types.
- Cost: paw has it.

**P2. Tests of the boundary itself: errors, not crashes.**

- What: call each function of the API with wrong arguments (wrong
  type, `nil`, a deleted id, a huge number, a string with a NUL) and
  check that each call gives a Lua error with a clear message, and
  not a panic, an abort or a stop of the kernel.
- Who: mlua's own tests (errors across the boundary, panics in
  callbacks); Neovim's API tests check the error text of each call;
  fuzzers of script bindings in game engines.
- Evidence: paw's rule 6 ("each failure gives a clear message, not a
  stack trace") is a property of the whole API, so a generated test is
  the cheapest proof.
- Cost: low, because the API list exists (P1).

**P3. One test command, several runners inside.**

- What: one command runs each language's own runner and joins the
  results. Each language keeps the runner that fits it.
- Who: rust-analyzer (everything is `cargo test`), Neovim (CMake runs
  unit, functional and old tests), Zed and Helix (Rust only).
- Evidence: an agent or a person runs one thing and gets one answer.
- Cost: paw has `nix flake check` for the lints and two commands for the
  tests. The review's P8 joins the two Lua runner paths.

**P4. Tiers.**

- What: a fast tier before a commit (seconds to a few minutes), a full
  tier before a merge, a long tier each night (fuzzing, mutation,
  coverage, many seeds), and a release tier (end-to-end, platforms).
- Who: rustc (bors tests the merge commit; "not rocket science"),
  Chromium and Google (test sizes small, medium, large), wasmtime
  (OSS-Fuzz all the time).
- Evidence: the fast tier keeps the loop short; the long tiers find
  rare bugs without a cost to each change.
- Cost: a written list of which check runs in which tier.

**P5. A flake policy: no retries, quarantine with an owner, find by
repetition.**

- What: a flaky test is a bug. Find flakes by repetition (stress runs,
  many seeds), by rerun on another host, or with the time moved. A
  test that flakes goes to quarantine: it still runs, it does not fail
  the build, and it has a ticket with an owner and a date.
- Who: Google (about 16 % of tests had some flakiness in 2016; flakiness
  goes up with the size of the test binary; in one team, about one
  flaky test in six was a real bug of the product); GitHub (rerun a
  failure three ways: same process, time shifted, other host; this
  found about 90 % of flakes; red builds from flakes went from 1 commit
  in 11 to 1 in 200; a ticket goes to the last person who changed the
  test).
- Evidence: the numbers above. GitHub's "time shifted" rerun matches
  paw's main source of flakes (time).
- Cost: a quarantine list, and the discipline to empty it.

**P6. Hermetic tests.**

- What: a test reads nothing from the machine that the test did not
  make: no home folder, no installed plugins, no network, no display of
  the user.
- Who: Nix builds (the sandbox enforces it), Bazel, Neovim (`-u NONE`,
  `NVIM_TEST_INTEG` for the tests that use the network).
- Evidence: the same result on each machine.
- Cost: paw has most of it (scratch `XDG_*`, scratch `HOME` for
  plugins, `--clean`, a private X display). The Lua suite does not run
  in the Nix sandbox yet.

**P7. Run only the affected tests.**

- What: from the changed files, choose the tests that can fail. Bazel
  and Buck do it from the build graph; small projects do it from path
  rules.
- Who: Google (TAP), Meta, Chromium; cargo-mutants `--in-diff` uses the
  same idea for mutants.
- Evidence: fast feedback on a large suite. It is not a replacement for
  the full run before a push.
- Cost: a map from paths to tests. A wrong map gives a false pass, so
  the full run stays before each push (paw's merge rule already says
  so).

### 2.5 TUI and GUI

**U1. Draw into a test backend and compare text.**

- What: draw the view into a grid in memory at a fixed size, and compare
  the text with a golden file.
- Who: ratatui (`TestBackend` and insta; colors are not in the
  snapshot), Helix, Neovim (through the UI protocol).
- Evidence: fast, certain, and close to what the user sees.
- Cost: low. paw has `api.ui_snapshot(w, h)` and `api.scene_cells`.

**U2. A few tests in a real pseudo-terminal.**

- What: start the real binary in a pseudo-terminal, send bytes, read
  the screen (expectrl, rexpect, termlens; vhs for recordings).
- Who: ratatui recommends it "for a few key user flows", next to fast
  `TestBackend` tests.
- Evidence: it tests the parts that a test backend skips: the terminal
  setup, the escape sequences, the reset at exit.
- Cost: slow and dependent on time. paw has one (`paw-tui/tests/join.rs`,
  escape sequences that arrive split).

**U3. GUI tests through the accessibility tree.**

- What: egui_kittest runs the egui app in the test process, finds a
  widget by its accessible name or role (AccessKit), clicks it, and
  steps the frame until the UI settles (`harness.run()`). Optional
  image snapshots with a per-pixel threshold and a count of failed
  pixels.
- Who: egui itself and egui apps (Rerun).
- Evidence: no X server, no OCR, no wait for time. The test runner steps
  frames, so the test is certain. The egui page itself says that image
  snapshots are slow and brittle across GPUs, and prefers normal tests
  or insta where possible.
- Cost: low for paw: `crates/paw-gui/src/gestures.rs` already has 28
  kittest tests. The window tests in `tests/window.rs` (45 tests, X
  server, tesseract) are the expensive part.

## 3. paw today

### 3.1 What paw does well

- **Offline render and the engine as a seam.** `paw.render` and
  `Engine::process` block by block give certain sound tests (A1). The
  engine tests (`crates/paw-engine/tests/*.rs`) are the model that the
  review names.
- **A real no-allocation check (A4)**, own allocator, with the pool's
  workers marked, for the engine and the plugin host.
- **API contract (P1).** `tools/apidoc.lua check`, the generated
  `docs/reference/api.md`, and Teal declarations.
- **One view, two frontends, tested.** `tests/scene_parity.lua` checks
  that a view lowered to cells is the same as its terminal drawing,
  for each view, at two sizes. This is a parity test that few
  projects have.
- **Real keys.** `T.keys` feeds keys through the keymap; the guides and
  the tutor's lessons are tests (externalized, data-driven tests in
  matklad's sense).
- **Static checks** in `nix flake check`: clippy, Teal, luacheck, the
  format, Vale, and the website.
- **nextest** with `retries = 0`, a slow timeout, and a test group for
  the window tests (R8).
- **A fuzzer of edits** (`bench/fuzz.lua`, and one short run of it in
  `tests/fuzz.lua`): random edits, undo, save and load, renders, with
  invariants. That is a property test of the whole program.
- **kittest** for the window's gestures (U3), in process.
- **Benchmarks apart from tests** (`bench/`, the bench results, a profile
  guide), and a written rule that speed is not a test.
- **Hermetic runs** (P6) for the suite: `--clean`, scratch `XDG_*`, a
  scratch home for plugins, a private display.
- **End-to-end scenarios with approved renders** (A2), in the release
  tier only.

### 3.2 Gaps

The review's gaps (time, quiescence, handshakes, the stepped backend,
pixels, the structure of the runner) are not repeated here. The gaps
below are new.

| # | Gap | Evidence |
| --- | --- | --- |
| G1 | No golden files for the screen. Tests search the screen for a string (`screen():find(...)`), so a wrong layout that still holds the string passes. | `api.ui_snapshot` is used through local `screen()` helpers in many files; no file under `tests/` holds an expected grid. |
| G2 | No golden files in Rust. The scene, the remote protocol, the project file, `.midi2` clips and the undo file are checked field by field, or not at all. | No `insta` or `expect-test` in any `Cargo.toml`. |
| G3 | No property tests in Rust. The parsers and the model (tempo map, MIDI 2 clips, XML, undo file, attribute maps) have example tests only. | No `proptest` or `quickcheck`. |
| G4 | No fuzzing of the parsers of files that come from outside: MIDI files, `.midi2` clips, project JSON, DAWproject XML, RPP, terminal input, the remote protocol. | No `fuzz/` folder. |
| G5 | No null tests that compare two ways to render. Sound tests check levels and frequencies of one render. | `T.render` callers check peaks and `T.frequency`; no test compares two renders sample by sample. |
| G6 | No test of the API boundary as a whole: wrong arguments to each `paw.api` function. | `tests/robust.lua` checks some calls by hand. |
| G7 | The engine has 13 integration-test binaries, each links `paw-engine` again. | `crates/paw-engine/tests/*.rs`. |
| G8 | No coverage report, Rust or Lua. paw-code says so in "Not in force yet". | paw-code, part 7. |
| G9 | No mutation tests. paw-code asks for "mutation as a lens" by hand only. | paw-code, part 3. |
| G10 | No written tiers. The checks before a commit, a merge, a push, a release are spread over the instructions for agents, memory notes and TASK-42. | The part "How to work" of the instructions for agents; the merge rule; TASK-42. |
| G11 | No way to find a flake by repetition in the Lua runner, and no quarantine list. | `tests/tools/suite.sh` has `only` and `plugins`, no `repeat`. |
| G12 | The fuzzer of edits has a seed, but a failure does not shrink, and only seed 1 runs in the suite. | `tests/fuzz.lua`. |
| G13 | Window tests in an X server with OCR, while the same crate already has kittest. | `crates/paw-gui/tests/window.rs` and `src/gestures.rs`. |
| G14 | No skill tells an agent which kind of test to write for which change (Rust or Lua, golden or example, render or meter). | `.claude/skills` has `prune-tests` and `paw-code` only. |

### 3.3 The review's tickets and the present research

| Review ticket | The present research |
| --- | --- |
| P1 (no speed in tests; the lint) | Kept. R10 adds counts and Gungraun as the home of numbers that load must not change. |
| P2 (clock, step, quiescence) | Kept. R13 adds a seed for the order of work later, on the same seam. |
| P3 (stepped backend) | Kept. A3 (null tests) needs only the offline render, so it can come first. |
| P4 (waits to steps) | Kept. |
| P5 (handshakes) | Kept. A5: the stub plugin is paw's "bad plugin". |
| P6 (kernel state in the leak check) | Kept. |
| P7 (remote and window barriers) | Changed: move most window tests to kittest (U3) in place of a new `window.texts()` control request. Keep a few X-server smoke tests. |
| P8 (one runner, binary check, times, shuffle) | Kept. Add `repeat` (L3, P5) and JUnit or TAP output for CI. |

## 4. What paw adopts, ranked

Tiers: **now** (small, no design question), **milestone** (the "Better
testing" milestone), **later**, **no**.

| Rank | Practice | Tier | Reason |
| ---: | --- | --- | --- |
| 1 | Screen golden files with bless (L2, U1): `T.expect_screen` on `api.ui_snapshot`, with style ids, files in `tests/screens/`, `PAW_BLESS=1` | milestone | Finds layout regressions that `find()` cannot; the main frontend is the terminal. |
| 2 | Null tests of the engine (A3): block sizes, threads, save and load, move and move back | now | Cheap, no golden, finds edge-of-block bugs; the engine is already certain. |
| 3 | A written tier list (P4) and a flake policy with quarantine (P5) | now | Agents need one place that says what runs when; no retries stays. |
| 4 | Contract test of the API boundary (P2): wrong arguments to each `paw.api` function give a Lua error and no crash | milestone | Rule 6 for the whole API at once; the API list exists. |
| 5 | insta in Rust (R3) for the scene, the remote protocol, the project file, `.midi2` and the undo file | milestone | Text formats that change often; one bless step in place of field checks. |
| 6 | proptest (R4) for round trips and invariants in `paw-core` (`.midi2`, XML, undo file, tempo map, attribute maps) | milestone | Finds edge cases of parsers and the model; regression files are committed. |
| 7 | Window tests through kittest (U3), X server and OCR only for smoke | milestone | Removes OCR and time from most window tests; kittest is already in the crate. Changes the review's P7. |
| 8 | `repeat` and shuffle in the Lua runner (L3), and a seeded fuzzer of edits with more seeds in the nightly tier (G12) | milestone | Finds flakes and order bugs before merge. |
| 9 | One `check` helper and inline project fixtures (R1, R2) for key-grammar tests | milestone | New key tests become one line of data; refactors touch one helper. |
| 10 | cargo-fuzz targets for parsers of outside files and terminal input (R5) | milestone (targets), nightly tier (runs) | These parsers read untrusted files. |
| 11 | One integration-test binary for `paw-engine` (R9) | now | Less link time; no change of behavior. |
| 12 | Coverage reports: cargo-llvm-cov with `show-env` across the Lua suite, luacov on request (R11, L6) | later | Useful to find dead code and untested branches; no floor. |
| 13 | cargo-mutants `--in-diff` as a review aid on `paw-core` and `paw-engine` (R6) | later | Makes "mutation as a lens" a tool; too slow for each merge. |
| 14 | Gungraun instruction counts for the engine hot path (R10) | later | A speed signal that load does not change; the shared machine makes wall time noisy. |
| 15 | RealtimeSanitizer on the engine tests (A4) | later | Finds locks and system calls on the audio thread, which the allocator does not. Evaluate first. |
| 16 | shuttle or loom on paw's own lock-free code (R7) | later | Only where paw has its own atomics protocol (15 engine files use atomics); rtrb is tested upstream. |
| 17 | clap-validator on the CLAP plugins that paw or its extensions make (A5) | later | Only for paw's own plugins; it does not test a host. |
| 18 | The Lua suite in the Nix sandbox (P6) | later | After the stepped clock and backend: no display or audio needed for most tests. |
| 19 | Affected-test selection for agents (P7) | later | A path map for the edit loop only; the full run stays before a push. |
| 20 | Miri | no (except a pure module with `unsafe` and no FFI) | Most unsafe code in paw is FFI (plugins, ALSA, LuaJIT), which Miri cannot run. |
| 21 | busted, tested, mini.test as runners | no | TASK-69: they cannot drive the kernel. Take their ideas (insulate, shuffle, repeat, tags) into paw's runner. |
| 22 | selene | no | luacheck and Teal cover it; one more linter is one more config. |
| 23 | mockall | no | Mocks of own code lower fidelity (matklad); paw uses real seams with two adapters. |
| 24 | googletest matchers | no | `assert_eq!` with a message is enough; a new assertion style is one more thing to learn. |
| 25 | Retries in nextest or in the Lua runner | no | A retry hides a flake; quarantine shows it. |
| 26 | A coverage floor | no | Agents would write tests for the number, against `prune-tests`. |
| 27 | Image snapshots of the window | no | Brittle across GPUs (egui's own advice); the scene parity test and kittest cover the content. |

## 5. Proposed skills

### 5.1 `rust-testing`

Description: "How to write and change Rust tests in paw: where a test
goes, which kind of test to write, golden files, property tests, null
tests of the engine, the no-allocation check, and what not to do. Use
it for each Rust change that adds or changes a test." It adds to
`rust-skills` (its testing rules) and `paw-code` part 3.

- **Choose the seam first.**
  - A pure function or a model type: a unit test in its module.
  - The engine: an integration test that calls `Engine::process` block
    by block. No real-time thread and no sleep.
  - The kernel through Lua: a Lua test, not Rust (see `lua-testing`).
  - The window: kittest in `src/gestures.rs` or its neighbor. The X
    server tests in `tests/window.rs` are smoke tests only.
- **Where tests live.** One integration-test binary per crate
  (`tests/it/main.rs`, a module per area). Helpers are modules of it,
  not `mod common;` copies.
- **One `check` helper per feature.** Tests give data to it. A test does
  not call the API under test by itself.
- **Golden files.** Use insta for a text output larger than about five
  lines: the scene, a protocol message, a file format. Inline
  (`assert_snapshot!(x, @"...")`) for short output, a file for long.
  Redact ids, paths and times. Run `cargo insta review`, read each
  diff, and name the accepted snapshots in the commit. Never accept
  with `INSTA_FORCE_PASS` or by a blind `accept`.
- **Property tests.** Use proptest for a round trip (decode of encode,
  load of save), an inverse (undo of a change), or an equivalence (two
  ways to compute one thing). Commit the files in
  `proptest-regressions/`. Keep the case count at the default in the
  normal run; the nightly tier can raise it.
- **Null tests of sound.** Where two ways to render must give the same
  sound, render both and compare sample by sample: bit-exact where the
  code is certain, a stated limit in dB where it is not, with the reason
  in a comment.
- **The audio thread.** A new message, device or path of the engine
  goes through `tests/no_alloc.rs`. Do not use `assert_no_alloc`.
- **Errors.** A fallible input has a test of its error: the variant
  and the message that the user sees.
- **No time.** No `thread::sleep`, no `Instant::now` in a test, no
  assertion on a duration (the review's rules). Speed goes to `bench/`.
- **No retry, no `#[ignore]` to hide a failure.** An `#[ignore]` test
  has a comment that names its ticket.
- **Fuzz targets.** A parser of outside input gets a target in `fuzz/`
  that calls the same `check` helper. A crash found by the fuzzer
  becomes a normal regression test.
- **Commands.** `cargo nextest run -p <crate>` in the edit loop;
  `cargo test --doc -p <crate>` when the crate has doc tests;
  `--profile gate` before a push.

### 5.2 `lua-testing`

Description: "How to write and change Lua and Teal tests in paw: the
runner and its helpers, real keys, screen golden files, renders, the
state that a test must make and put back, and what not to do. Use it
for each change of `tests/`, `extensions/*/tests*.lua` or the tutor's
lessons."

- **The runner.** Tests run inside the kernel (`tests/suite.lua`), all
  files in one process. Use the helpers of `T`; do not copy them into
  a file (`start`, `screen`, `wait_for`).
- **Start clean.** Start from `T.fresh()` or `T.start()`. Set each
  option that the test needs. Take ids from the kernel. Write files
  under `T.scratch`. Put back what you change with `T.after`.
- **Real keys for behavior of the user.** Use `T.keys`, not the
  function behind the key, for a test of what a user does.
- **One `check` per feature.** For a key grammar: `check(fixture, keys,
  expected)`, where the fixture is a short text project (tracks, clips,
  notes, a cursor marker).
- **The screen.** For layout, use `T.expect_screen(name, w, h)` against
  a golden grid in `tests/screens/`. Bless with `PAW_BLESS=1`, read the
  diff, and name the blessed files in the commit. Use `find()` on the
  screen only to check that one text exists, not a layout. Keep a grid
  small: the smallest size and region that show the behavior.
- **Sound.** Check sound with `T.render`, or with stepped blocks after
  the review's P3. Do not read a live meter after a wait. Prefer a null
  test (two renders that must be the same) to a level with a tolerance.
- **No time.** The review's rules: no `paw.wait(ms)`, no `api.sleep`,
  no `api.now()` deadlines, no `T.quick`. Wait for a state, or advance
  the clock.
- **Errors for the user.** A command or key that can fail has a test
  of its message (rule 6), not only of the success.
- **Undo.** A test of an action also checks that one `u` undoes it.
- **Skips.** A test that needs a plugin or a tool returns a skip reason
  (the runner prints it). Never skip in silence.
- **Teal.** A test of a `.tl` module can be Lua. The module itself
  passes `cyan check`; the type check is part of the suite.
- **Flakes.** If a test fails once and passes again, run it with
  `suite.sh repeat N only "<name>"` (when it exists). Do not change a
  time or a tolerance to make it pass. Put it in the quarantine list
  with a ticket if you cannot fix it now.
- **Extensions.** An extension's tests are in its folder
  (`tests*.lua`). A project made with the extension must open and play
  without it: test that too.

## 6. Proposed tickets for a "Better testing" milestone

Checked with `backlog search --plain` (read only) for "test", "fuzz",
"snapshot", "coverage", "mutation", "golden", "CI", "property",
"kittest", "validator", "lint", "flake". No ticket covers golden
screens, property tests, fuzzing, mutation, coverage or null tests.
Overlaps found: TASK-121 (order), TASK-42 (CI, m-1), TASK-24 (e2e
goldens), TASK-69 (runner, done), TASK-70 (luacheck, done), TASK-98
(workspace lints), TASK-133 (apidoc check in the flake), TASK-114. The
milestone holds the review's P1 to P8 too, unless the owner keeps them in
m-3 and m-6 (question 1).

### Tiers and the flake policy, written (BT1)

- **Description:** Write one page for agents (in the skill `paw-code`
  and a short part of the instructions for agents) that lists each check and its tier:
  edit loop (one crate, `only`), before a commit (the affected
  tests, the lints), before a push (full suite, `nix flake check`,
  `--profile gate`), nightly (fuzz runs, more proptest cases, more
  fuzzer seeds, mutants on the diff of the day, coverage report), release
  (e2e, plugins, platforms, TASK-42). Write the flake policy: no
  retries; a test that flakes goes to `tests/quarantine.txt` with a
  ticket; a quarantined test runs and reports, and does not fail the
  run; the list only gets shorter.
- **Acceptance criteria:** (1) the tier list exists and names each
  command; (2) the runner reads `tests/quarantine.txt` and prints
  "quarantined" for a failure of a listed test; (3) an entry with no
  ticket id fails the runner.
- **Dependencies:** none.
- **Overlaps:** TASK-42 (the release tier), the review's P8, the memory
  rule on merges.

### Null tests of the engine (BT2)

- **Description:** Engine integration tests that render one project
  two ways and compare sample by sample: blocks of 64, 128 and 512
  frames; one thread and four; a clip moved and moved back; render,
  save, load, render; a bypassed device and no device; a subproject
  and its expanded tracks (where the design says they sound the
  same). Bit-exact where the code is certain; else a stated limit.
- **Acceptance criteria:** (1) each case is one line of a table in one
  test; (2) a test fails when a deliberate off-by-one is put at the edge
  of a block (checked once by hand, named in the commit); (3) no golden
  file is needed.
- **Dependencies:** none.
- **Overlaps:** TASK-16 (sleep of devices: a sleeping device must null
  with an awake one at silence).

### One integration-test binary for `paw-engine` (BT3)

- **Description:** Move `crates/paw-engine/tests/*.rs` into
  `tests/it/main.rs` with modules. Keep `no_alloc.rs` as its own binary
  (it sets a global allocator for its process).
- **Acceptance criteria:** (1) the same test names pass; (2) the link
  time of `cargo nextest run -p paw-engine --no-run` is lower (number in
  the commit, for information).
- **Dependencies:** none.
- **Overlaps:** none.

### Screen golden files for the terminal (BT4)

- **Description:** Add `T.expect_screen(name, width, height, opts)` to
  `tests/suite.lua`: it takes `api.ui_snapshot`, adds style ids in the
  manner of Neovim's `{1:text}`, and compares with
  `tests/screens/<file>/<name>.txt`. With `PAW_BLESS=1` it writes the
  file. On a failure it prints a diff and the path. Move 10 tests that
  check layout with `find()` to it (statusline, piano roll, mixer
  strip, help, picker, arrange). Write the rule in `lua-testing`.
- **Acceptance criteria:** (1) a missing golden file fails, and the
  message tells how to bless; (2) a golden file that no test uses
  fails the runner (no dead files); (3) the 10 tests pass, and each
  fails when a column of its view moves by one cell (checked once).
- **Dependencies:** the review's P2 is better first (a screen at
  quiescence), but not required for views that draw at once.
- **Overlaps:** `tests/scene_parity.lua` (keep; it checks the window
  against the terminal, this checks the terminal against a file).

### Insta for the Rust text formats (BT5)

- **Description:** Add insta as a dev-dependency of `paw-scene`,
  `paw-proto` and `paw-core`. Snapshot tests for: a scene of each kind
  of node, the remote protocol messages, a project folder written to
  disk (as a list of files and their text), a `.midi2` clip, the undo
  file. Redactions for ids and paths.
- **Acceptance criteria:** (1) `cargo insta test` passes; (2) CI fails
  on a new or changed snapshot that is not committed (`INSTA_UPDATE=no`
  in CI); (3) `rust-testing` has the rules.
- **Dependencies:** none.
- **Overlaps:** TASK-24 (e2e goldens), TASK-98.

### Proptest for the model and the file formats (BT6)

- **Description:** Property tests in `paw-core`: `.midi2` clip decode of
  encode; the undo file round trip; XML (DAWproject) round trip of the
  parts paw writes; the tempo map (beats to seconds to beats); the
  attribute map; an undo of a random change gives the old project.
  Commit `proptest-regressions/`.
- **Acceptance criteria:** (1) each property is one test; (2) the
  normal run stays under 10 s for the crate (counted cases, not a
  timer); (3) the nightly tier runs them with `PROPTEST_CASES=10000`.
- **Dependencies:** BT1 (the nightly tier) for criterion 3.
- **Overlaps:** none.

### A contract test of the API boundary (BT7)

- **Description:** A Lua test that reads the API list (the data that
  `tools/apidoc.lua` reads) and calls each `paw.api` function with wrong
  arguments: no arguments, a wrong type for each one, a deleted id, a
  negative and a huge number, a long string. Each call must give a Lua
  error with the function's name in the message, or a documented
  result. No call may panic, abort, stop answering or leave the project changed
  without an undo step. An allow-list holds the functions that cannot
  be called safely in a test (for example the ones that quit).
- **Acceptance criteria:** (1) every API function is called or is on
  the allow-list with a reason; (2) a panic in a Rust function of the
  API fails the test with the function's name; (3) the bugs found have
  their own fixes and tests.
- **Dependencies:** none.
- **Overlaps:** `tests/robust.lua`, TASK-133 (apidoc as readers and
  writers: the test can use its reader).

### Window tests through kittest (BT8)

- **Description:** Move each window test of `crates/paw-gui/tests/window.rs`
  that finds text by OCR or waits after a gesture to kittest in the
  crate, with the fixture kernel that `gestures.rs` uses. Keep at most 5
  X-server tests as smoke tests (the window opens, draws text, takes a
  key, closes; idle counts after the review's P7).
- **Acceptance criteria:** (1) at most 5 tests use tesseract; (2) no
  `pause()` after a gesture in a kittest test; (3) `cargo test -p
  paw-gui` time is lower (for information).
- **Dependencies:** none for the move. The idle counts need the review's
  P7.
- **Overlaps:** replaces the window part of the review's P7
  (`window.texts()` is then not needed); TASK-42.

### The Lua runner with repeat, shuffle and output for CI (BT9)

- **Description:** `suite.sh repeat N only "<words>"` (stop at the first
  failure, print the run number); `--shuffle <seed>` (the review's P8);
  a TAP or JUnit file in `target/test-scratch/` for CI; the seed of
  `bench/fuzz.lua` from the command line, with seeds 1 to 50 in the
  nightly tier.
- **Acceptance criteria:** (1) `repeat 20` of a test that depends on
  order or time fails within the 20 runs (shown on one known flake);
  (2) the CI file lists each test with its result and its skip reason.
- **Dependencies:** none. Merge with the review's P8 if both are open.
- **Overlaps:** P8, TASK-42, TASK-121.

### One `check` helper and text fixtures for key tests (BT10)

- **Description:** A fixture format for a small project in a Lua string
  (tracks, clips with notes, a cursor and a selection marker) and a
  helper `T.check_keys(fixture, keys, expected_fixture)`. Move the key
  tests of one area (the piano roll motions) to it as the first user.
- **Acceptance criteria:** (1) the format has a reference comment in
  `tests/suite.lua`; (2) a failure prints the actual fixture, ready to
  paste; (3) the moved tests are shorter (lines in the commit).
- **Dependencies:** none.
- **Overlaps:** TASK-121 (`T.start`).

### Fuzz targets for outside input (BT11)

- **Description:** A `fuzz/` crate with cargo-fuzz targets: the MIDI
  file reader, the `.midi2` clip reader, the project JSON loader, the
  DAWproject and RPP readers (in their extensions, when they are
  Rust), the terminal input parser (`paw-tui`, escape sequences), and
  the remote protocol decoder. Each target calls the same code as the
  product and checks "an error, not a panic". CI builds the targets
  (so they keep building); the nightly tier runs each for a fixed
  count of runs.
- **Acceptance criteria:** (1) each target builds in the flake or in CI;
  (2) each crash found becomes a regression test in the crate;
  (3) the nightly command is in the tier list (BT1).
- **Dependencies:** BT1.
- **Overlaps:** TASK-106 (split escape sequences), TASK-42.

### The two testing skills (BT12)

- **Description:** Write `.claude/skills/rust-testing` and
  `.claude/skills/lua-testing` from part 5 of the present research, after BT4,
  BT5 and BT9 exist (so each rule names a real helper). Link them from
  `paw-code` part 3 and from the instructions for agents. Internal text, STE.
- **Acceptance criteria:** (1) each rule names a command or a helper
  that exists; (2) `paw-code` part 3 links them and does not repeat
  them.
- **Dependencies:** BT4, BT5, BT9; the review's P1 (the time rules).
- **Overlaps:** `prune-tests`, `rust-skills` (its testing rules).

### Later (not in the milestone)

- Coverage report (cargo-llvm-cov with `show-env` over the Lua suite;
  luacov on request), in the nightly tier, no floor.
- cargo-mutants `--in-diff` as a review aid, run by hand or nightly on
  `paw-core` and `paw-engine`.
- Gungraun benchmarks of `Engine::process` for a fixed project.
- RealtimeSanitizer: evaluate `rtsan-standalone` on the engine tests.
- shuttle on paw's own lock-free code, after a list of it.
- clap-validator on paw's own CLAP plugins (in their extensions).
- The Lua suite as a Nix check, after the review's P2 and P3.
- A path map for affected tests in the edit loop of agents.

## 7. Questions for the owner

1. **One milestone for all test work?** The review put P1 and P6 in m-3
   and the rest in m-6. Recommended: a new milestone "Better testing"
   with the review's P2 to P5, P7 and P8 and BT1 to BT12; P1 and P6
   stay in m-3, because they are small and remove the reported flakes
   now.
2. **Golden files for the terminal screen (BT4)?** A layout change then
   needs a bless of the files it changes. Recommended: yes, for about
   10 views at small sizes; `find()` stays for "this text exists".
3. **New dev-dependencies: insta and proptest (BT5, BT6)?** Both are
   the common choice of the Rust ecosystem and have no runtime cost.
   Recommended: yes.
4. **A fuzz crate that needs nightly Rust (BT11)?** It builds only in
   CI and in the nightly tier; the normal build stays on stable.
   Recommended: yes, as a separate crate that is not in the workspace's
   default members.
5. **A quarantine list (BT1)?** It lets a known flake run without
   failing a merge, under a ticket. The alternative is today's practice
   (an agent decides "only timing"). Recommended: yes, with the rule
   that each entry has a ticket and the list only gets shorter.
6. **Move the window tests to kittest (BT8) in place of the review's
   `window.texts()` request?** Recommended: yes. kittest is in the crate
   already, it needs no X server, and it steps frames. The X server
   stays for 5 smoke tests.
7. **A nightly tier on this machine?** Fuzzing, many seeds and mutants
   use machine time, and the machine is shared. Recommended: run the
   nightly tier in CI only (TASK-42), not on the local machine, and
   keep the local tiers to the edit loop and before a push.

## Owner decisions (2026-11-22)

The owner approved every recommendation of this document and of the
other testing document ([test-suite-review.md](test-suite-review.md),
[testing-practices.md](testing-practices.md)), as each document
recommends:

- An own small `Clock` trait (`WallClock`, `ManualClock`), not the
  crate `metrique-timesource`.
- `api.now()` becomes the schedule clock, which a test can control. A
  new `api.real_ms()` gives wall time for budgets.
- No speed checks in tests at all. Speed goes to `bench/`.
- A live tier of about 3 % of the tests.
- Shards (`suite.sh -j 4`) as the default only after P4 (TASK-149).
- Golden files for the terminal screen.
- insta and proptest as dev-dependencies.
- A fuzz crate outside the default members of the workspace.
- A quarantine list of flaky tests. Each entry has a ticket, and the
  list can only get shorter.
- The nightly checks run in CI only.
- **The window is paused.** The owner: "We are deprioritizing work on
  paw-gui, we focus on terminal-first right now. Tests for paw-gui
  should not be run until we decide to work on it again. It should also
  not be built until then." paw-gui is not a default member of the
  workspace. Each window ticket has the priority low, and its title
  starts with "Window (paused):".

The tickets (the milestone "Better testing" is m-12). P1 to P8 are the
tickets of the review; BT1 to BT12 are the tickets of the practices
document.

| Ticket | Source | Milestone | Priority | Depends on |
| --- | --- | --- | --- | --- |
| TASK-143 No speed checks; the rules and a lint against time | P1 (T1, T2) | m-3 | High | none |
| TASK-144 Kernel state in the leak check, the utau helper, no literal ids | P6 (T7) | m-3 | High | TASK-121 |
| TASK-145 The tiers, written, and a quarantine list | BT1 | m-12 | High | none |
| TASK-146 A manual clock, one turn of the loop, quiescence | P2 (T3, T4) | m-12 | High | TASK-143 |
| TASK-147 A stepped audio backend | P3 (T5) | m-12 | High | TASK-146 |
| TASK-148 Handshakes with plugins and helpers | P5 (T6) | m-12 | Medium | TASK-146 |
| TASK-149 The waits become steps; a live tier of about 3 % | P4 (T4) | m-12 | Medium | TASK-146, 147, 148, 151 |
| TASK-150 Remote: a sync barrier in place of quiet periods | P7, remote part (T8) | m-12 | Medium | none |
| TASK-151 Lua runner: one path, binary check, times, repeat, shuffle, CI output | P8 (T9) and BT9 | m-12 | Medium | TASK-121 |
| TASK-152 Golden files for the terminal screen | BT4 | m-12 | High | none |
| TASK-153 Null tests of the engine | BT2 | m-12 | Medium | none |
| TASK-154 One integration-test binary for paw-engine | BT3 | m-12 | Low | none |
| TASK-155 insta snapshots for the text formats | BT5 | m-12 | Medium | none |
| TASK-156 Property tests for the model and the file formats | BT6 | m-12 | Medium | TASK-145 |
| TASK-157 Contract test of the API boundary | BT7 | m-12 | Medium | none |
| TASK-158 One check helper and text fixtures for key tests | BT10 | m-12 | Low | none |
| TASK-159 Fuzz targets for input from outside | BT11 | m-12 | Medium | TASK-145 |
| TASK-160 Window (paused): kittest, smoke tests with a sync barrier and counts | P7, window part (T8) and BT8 | m-12 | Low | TASK-146 |

Merged: P8 and BT9 are one ticket (TASK-151). The window part of P7 and
BT8 are one ticket (TASK-160), with kittest in place of `window.texts()`.
BT12 (the two skills) is done in the setup commit: the skills
`rust-testing` and `lua-testing` exist, and each ticket that adds a
helper changes them in the same commit. The items under "Later" of the
practices document have no ticket yet.

Notes in the existing tickets, in place of duplicates: TASK-121,
TASK-114, TASK-42, TASK-24 and TASK-133.
