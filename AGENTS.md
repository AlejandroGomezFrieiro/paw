# Instructions for agents

This file is for AI agents and for people who change paw. Read it before
you change anything. The rules here are not optional.

You are a co-owner and long-term maintainer of the codebase. Design
choices are up to you.

## What paw is

paw is a personal audio workstation for Linux. A small Rust kernel plays
the sound, keeps the project and hosts plugins. Everything that the user
touches is Lua over one API, `paw`, and new code is Teal, Lua with
types. The model is Neovim: a small core, a modal grammar of keys, Ex
commands, and a configuration that can change everything.

## The philosophy

1. **Terminal first.** Each feature works in the terminal before the
   graphical window. The terminal is the main frontend, not a fallback.
2. **One view, two frontends.** A view is written once in Lua. The kernel
   sends it as a scene to each frontend. Never write a second view that
   only the window has. See
   [About scenes](docs/explanation/about-scenes.md).
3. **The key rule.** `h j k l w b e 0 ^ $ gg G` only move. `+ -` and
   `Ctrl-a` `Ctrl-x` change the main value, `[ ]` the second value. `< >`
   are time. `K` describes. `Esc` cancels. The keys of one view go on
   `<localleader>`. See [The key rule](docs/reference/key-rule.md).
4. **MIDI is the truth.** Notes, controllers and clips are the data. An
   extension keeps its own data in `meta` and never owns clip data. A
   project must open and play without the extension. See
   [About MIDI as the truth](docs/explanation/about-midi-as-the-truth.md).
5. **A small core, extensions for the rest.** A feature that is not
   needed by all users is an extension. Core changes for an extension are
   generic, not specific to that extension. See
   [About the core and extensions](docs/explanation/about-core-and-extensions.md).
6. **Each action is undoable and gives feedback.** One user action is one
   undo step. Each action says what it did. Each failure gives a clear
   message, not a stack trace.
7. **Fast keys.** A key stays well under 100 ms on a large project.
8. **New code is written in Teal.** Teal is Lua with types. A new module
   of the runtime is a `.tl` file, and so is a new extension. A Lua file
   that changes much moves to Teal. Lua stays only with a written reason,
   for example the FFI code of `dsp.lua`. Write no `any` where a value has
   a shape. See [About Teal in paw](docs/explanation/about-teal.md), and
   use the skill in [.claude/skills/teal](.claude/skills/teal/SKILL.md)
   for each `.tl` file that you write or change.

For each Rust change, use the skill in
[.claude/skills/rust-skills](.claude/skills/rust-skills/SKILL.md). Prefer
clear traits and structs to long functions and flags, and avoid its
anti-patterns. Use the recommended crates, as its page
[paw-crates.md](.claude/skills/rust-skills/paw-crates.md) says: do not
write what a crate such as `mlua`, `clap` or `serde` already does. The
audio thread rules come first: no lock, no allocation and no wait on that
thread.

To write an extension, use the skill in
[.claude/skills/paw-extension](.claude/skills/paw-extension/SKILL.md).

For each change of code, use the skill in
[.claude/skills/paw-code](.claude/skills/paw-code/SKILL.md). It gives the
loop: make it work, prove it with tests, then do three rounds of
refactor (logic, responsibility, consistency and comments). It also
gives the rules for style, tests, maintainability, comments and logic.

For each Rust test that you add or change, use the skill in
[.claude/skills/rust-testing](.claude/skills/rust-testing/SKILL.md).
For each Lua or Teal test, use the skill in
[.claude/skills/lua-testing](.claude/skills/lua-testing/SKILL.md).

## Documentation standards

All documentation follows three standards. The skill in
[.claude/skills/diataxis-docs](.claude/skills/diataxis-docs/SKILL.md)
gives the details. Read it before you write or change a page.

- **Diátaxis.** Each page is one of four kinds: a tutorial, a how-to
  guide, a reference page or an explanation. The pages are in
  `docs/tutorials`, `docs/how-to`, `docs/reference` and
  `docs/explanation`. [docs/README.md](docs/README.md) lists them.
- **Two styles of language.** External pages are for the users of paw.
  They use the skill `plain-writing` in
  [.claude/skills/plain-writing](.claude/skills/plain-writing/SKILL.md).
  Load it before you write or change an external page, and read its
  `PAW.md`. Internal text is for the people and agents that change paw.
  It uses ASD-STE100 Simplified Technical English: short sentences,
  active voice, the present, past and future tenses only, one word for
  one thing, American English.
  - External: `README.md`, `docs/`, the READMEs and `doc/` pages of the
    extensions, the READMEs of the crates and of `web/`, the tutor's lessons, and the
    doc comments that `tools/apidoc.lua` turns into
    `docs/reference/api.md`.
  - Internal: `AGENTS.md`, `.claude/` (the skills), `bench/`, Backlog
    tickets, design documents, the other code comments, commit messages,
    pull request text and replies in chat.
- **Vale.** Vale checks every Markdown file with the project's styles.
  `.vale.ini` gives each kind of file its rules, and each rule is an
  error or off: there is no warning level. Run
  `nix develop -c tools/vale.sh` on the files that you change. Vale
  must report 0 alerts. A hook runs Vale after each Markdown edit, and
  `nix flake check` fails on any alert.

  | Kind | Files | Rules |
  | --- | --- | --- |
  | External | `README.md`, `docs/`, READMEs and `doc/` pages of the extensions and the crates, `web/*/README.md` | `Plain`, `AiTells`, `alex`, `write-good`, `Vale` (words), and the STE rules that agree with plain writing. Readability is off. |
  | Generated | `docs/reference/api.md`, `docs/tutorials/course/` | The external rules. Fix the doc comment or the lesson, and run the generator. |
  | Internal | `AGENTS.md`, `.claude/`, `bench/*.md` | `STE`, with the grade levels. |
  | Not checked | `bench/RESULTS.md` | None: it is a dated log. |

Other rules for documentation:

- The user guide is for musicians first. Write about what the user
  wants to do, in the words of the user.
- Each fact is true. Examine the code, or run paw to see the result. The
  steps of a guide have a test: tutorials in `tests/guides.lua`, how-to
  guides in `tests/guides_howto.lua` and the other `tests/guides_*.lua`.
- A change that alters a behavior, a format, a file, a command, a key or
  an option also changes each page that tells about it, in the same
  commit. Before you commit, search `README.md`, `AGENTS.md`, `docs/`,
  `bench/`, the READMEs of the crates and extensions, the `doc/` pages
  of the extensions, and
  `.claude/skills` for the old words and names. Fix each sentence that is
  no longer true. For example, when projects became folders, the README
  still said "A project is a JSON file". In your report, give the search
  that you did and the pages that you changed.
- Never edit generated files. `docs/reference/api.md` comes from the doc
  comments through `tools/apidoc.lua`. The course in
  `docs/tutorials/course` comes from the tutor's lessons.
- Each extension has a README that `:help` shows. The README, or a page
  in the `doc/` folder of the extension, names every command and key of
  the extension, and a test makes sure of this. A long reference goes in
  `doc/reference.md`, and the README links it.

## How to work

Run the commands in the dev shell of the flake. Start your session in
`nix develop`. Or use `direnv` with the file `.envrc`. With
`nix-direnv`, the shell stays in a cache until `flake.nix` or
`flake.lock` changes. In the dev shell, do not use the prefix
`nix develop -c`. Each `nix develop -c` reads the flake again, and
in a `git worktree` with changes it also copies the files into the
store.

Use `cargo check` and `cargo clippy` for most checks of Rust: they do
not link. A dev build (`cargo build`, the default profile) links with
mold and is incremental, and it is faster to make than a release build.
A change of Lua or Teal needs no build. Test it with a binary of main
and `tools/dev-runtime.sh`. The how-to guide on the tests tells how.

```sh
nix develop -c cargo check -p <crate>          # most checks of Rust: no link
nix develop -c cargo build --release -j 8      # the Lua runtime is in the binary: build first
nix develop -c tests/tools/suite.sh            # the Lua tests
nix develop -c tests/tools/suite.sh only <words>
nix develop -c cargo test --release -p <crate> # the Rust tests of a crate
nix develop -c target/release/paw --clean --no-plugins -l tools/apidoc.lua check
nix develop -c tools/tlcheck.sh                 # cyan check on all .tl files (the suite does it too)
nix develop -c luacheck .                       # unused and undefined names in the .lua files
nix develop -c tools/fmtcheck.sh                # every Lua and Teal file formatted (`fix` formats them)
nix develop -c tools/vale.sh                   # the docs
nix build .#website                            # the manual as a static site (tools/website/build.sh)
nix flake check                                # all of the checks
```

- Each change of behavior has a test. A fix of the user experience has a
  test that uses the real keys.
- No test depends on time or load: no sleep, no deadline as an
  assertion, no count of frames. Wait for an event or a state. A time in
  milliseconds goes to `bench/`. A test checks behavior, not speed.
- Check that a thing does not happen only after a sync point: first let
  the kernel do its work (a state, a block, a sync request), and go past
  each timer that could make it happen. "Nothing came in 300 ms" is not
  a check.
- A test is fully self-contained. It reads nothing of the machine: not
  the home folder, not the installed plugins, not the user name, the
  fonts, the desktop bus or the network. `tests/tools/env.sh` (Lua) and
  `sealed::seal` in `crates/*/tests/sealed/mod.rs` (Rust) give a scratch
  home, scratch XDG and runtime folders, empty plugin folders and the
  user name `paw-test`. A Lua test of `~` uses `T.home()`. Mock what a test needs: the stub CLAP
  plugin, a fake behind a trait, or a scratch folder. Run paw by hand
  only through `tests/tools/run.sh`.
- A flaky test is a bug in the test. No retries. Do not change a time or
  a tolerance to make it pass. If you cannot fix it now, put it in the
  quarantine list `tests/quarantine.txt` with a ticket. A quarantined
  test runs and reports, but does not fail the run. Each entry has a
  ticket, and the list only gets shorter.
- Keep the tests to a minimum. A test guards one behavior that the user or
  a caller relies on, and fails only when that behavior breaks. Before you
  commit, apply the skill in
  [.claude/skills/prune-tests](.claude/skills/prune-tests/SKILL.md) to the
  tests that you added or changed. Delete each test that guards no
  behavior, and each test that another test already covers.
- The window (`crates/paw-gui`) is paused. The work is on the terminal
  now. Do not change, build, check or test `paw-gui` until the owner
  starts the work on the window again. `cargo build`, `cargo check` and
  `cargo test` at the top of the workspace do not build it. A change of
  `paw-scene` can stop the build of the window. Write it in your report.
- Do not run `tests/tools/loaded.sh` unless the owner asks for it. It
  puts a heavy load on the machine.
- Do not run the end-to-end tests (`tests/tools/e2e.sh`). They are for
  CI and for the release check before a tagged version. Only the agent
  that builds them, or the owner, runs them.

## Safety and privacy

- Tests use `--audio null`, a private X display and their own
  `XDG_*` folders. Never use the owner's display, audio devices or
  configuration (`~/.config/paw`).
- Never write into the owner's data folders (for example
  `~/.local/share/OpenUtau`).
- Never name the owner's personal projects that are not published, and
  never write a path in the owner's home folder into the repository.

## Commits

- Commit when the tests pass. Push only when the owner asks.
- Keep the code style of the file that you change.
