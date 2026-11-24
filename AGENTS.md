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
4. **Lanes are the truth.** Source lanes hold the data. A derived lane
   is a recipe plus its kept result. A project opens and plays without
   the extension or program that made a derived lane. An extension keeps
   its own data in `meta` and never owns the data of a source lane. See
   [About MIDI as the truth](docs/explanation/about-midi-as-the-truth.md).
   The public page tells the design of today, and it changes when lanes
   of each kind exist.
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

## Skills

Load the skill for each kind of work with the Skill tool, before the
first edit of that kind. The skills hold the rules and the commands.

| Work | Skill |
| --- | --- |
| Each change of code: the loop, three refactor rounds, the tiers of checks (part 7) | `paw-code` |
| Rust code. Prefer traits and structs to long functions and flags. Use the crates of its page `paw-crates.md`. On the audio thread: no lock, no allocation, no wait. | `rust-skills` |
| A Rust test | `rust-testing` |
| A `.tl` file | `teal` |
| A Lua or Teal test, or a lesson of the tutor | `lua-testing` |
| Before a commit with tests: delete the tests that guard no behavior | `prune-tests` |
| An extension | `paw-extension` |
| A design, a contract, an ADR | `architecture` |
| A page of the docs, a README | `diataxis-docs` and `plain-writing` |
| A GIF | `paw-gifs` |

## Architecture

The architecture documentation is the source of truth for the target
design of paw. It has arc42 sections, one decision record (ADR) for
each decision, and a roadmap. Each section tells what paw is now and
what paw is built to be.

The folder `architecture/` is at the top of the owner's checkout. It
is local to that machine, and git does not keep it. In a clone it is
absent. Then the pages in `docs/explanation` give the design.

Use the skill in
[.claude/skills/architecture](.claude/skills/architecture/SKILL.md)
before you write a design, start a large change, or change a
contract. A contract is a trait, a saved type, a file format, a
`paw.*` function, a message of the protocol, or a layer.

- Do not change the design without an ADR. Agents propose an ADR, and
  the owner accepts it.
- A change of a contract updates the architecture documentation in the
  same work.
- The container is a **part**, and a row inside a part is a **lane**.
  The code, the API, the files and the user pages use these words. Do
  not use the word "track" for the container. The word "track" stays
  only in its other senses: a track of a MIDI file, the sound track of
  a video, a track of another program or file format, and to track a
  value. `tools/partlint.lua` checks this, and its allow-list
  `tools/partlint-allowed.txt` gives the reason for each exception.

## Documentation

- Each page is one of the four kinds of Diátaxis, in `docs/tutorials`,
  `docs/how-to`, `docs/reference` or `docs/explanation`.
  [docs/README.md](docs/README.md) lists them.
- External text is for the users of paw: `README.md`, `docs/`, the
  READMEs and `doc/` pages of the extensions and the crates, the tutor's
  lessons, and the doc comments of the API. It follows `plain-writing`
  and its `PAW.md`. The user guide is for musicians first.
- Internal text is for the people and agents that change paw: this
  file, `.claude/`, `bench/`, tickets, designs, the architecture
  documentation, the other code comments, commit messages and replies in
  chat. It is in ASD-STE100 Simplified Technical English.
- Vale checks each Markdown file with the rules that `.vale.ini` gives
  its kind, and must report 0 alerts: `tools/vale.sh <files>`. A hook
  runs it after each edit of Markdown.
- Each fact is true: examine the code, or run paw. The steps of a guide
  have a test in `tests/guides*.lua`.
- A change of a behavior, a format, a file, a command, a key or an
  option changes each page that tells about it, in the same commit.
  Search `README.md`, `AGENTS.md`, `docs/`, `bench/`, the READMEs and
  `doc/` pages, and `.claude/skills` for the old words, and give the
  search in your report.
- Never edit a generated file. `docs/reference/api.md` comes from the
  doc comments (`tools/apidoc.lua`), and `docs/tutorials/course` from the
  tutor's lessons.
- Each extension has a README that `:help` shows. It, or a page in its
  `doc/` folder, names each command and key of the extension.

## How to work

- Each session of Claude Code in the checkout runs its commands in the
  sandbox of `.claude/settings.json`. Start an agent with
  `nix run .#agent`: it adds limits on processes and memory
  ([the guide](docs/how-to/run-a-coding-agent-with-limits.md)).
- Work in the dev shell of the flake (`nix develop`, or `direnv` with
  `.envrc`). Inside it, do not add the prefix `nix develop -c`.
- The commands of each tier of checks are in the skill `paw-code`, part
  7. `nix flake check` runs all of them. A change of Lua or Teal needs
  no build: use a binary of main and `tools/dev-runtime.sh`
  ([Run the tests](docs/how-to/run-the-tests.md)).
- Each change of behavior has a test. A fix of the user experience has a
  test that uses the real keys.
- A test checks behavior. It waits for an event or a state, and its
  result does not depend on time or load. A time in milliseconds goes
  to `bench/`.
- A test reads nothing of the machine: `tests/tools/env.sh` and
  `sealed::seal` give it a scratch home and folders. Run paw by hand only
  through `tests/tools/run.sh`.
- A flaky test is a bug in the test. No retries. If you cannot fix it
  now, add it to `tests/quarantine.txt` with the fix that it waits for.
- Keep the tests to a minimum: each one guards a behavior that the user
  or a caller relies on.
- The window (`crates/paw-gui`) is paused: do not change, build, check
  or test it. A change of `paw-scene` can stop its build: say so in your
  report.
- Some rules run by themselves. The hook `.githooks/pre-commit` refuses a
  commit with a leftover of a merge, an id of the local task board, or a
  lint that fails. `tools/guard-hook.py` refuses the commands that put a
  load on the machine that it cannot carry. `tests/tools/suite.sh` waits
  for a slot of the machine.
- A review of a change reads `CODING_STANDARDS.md`: the rules that need
  judgment.

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
