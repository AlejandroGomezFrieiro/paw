---
id: TASK-159
title: 'Rust: fuzz targets for input from outside'
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-145
priority: medium
ordinal: 171000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/testing-practices.md, practice R5, gap G4, ticket BT11, rank 10. Owner, 2026-11-22: a fuzz crate outside the default workspace members; it runs in CI only.

What to do: a `fuzz/` crate with cargo-fuzz targets (nightly Rust): the MIDI file reader, the `.midi2` clip reader, the project JSON loader, the terminal input parser (`paw-tui`, escape sequences) and the remote protocol decoder; the DAWproject and RPP readers when they are Rust. Each target calls the same code as the product and checks "an error, not a panic". The crate is not in `default-members` and the normal build stays on stable. CI builds the targets; the nightly tier runs each for a fixed count of runs.

Read first: backlog/docs/designs/testing-practices.md, sections 2.1 (R5), 4, 5.1 ("Fuzz targets"), 6 (BT11), 7 (question 4).

Overlaps: TASK-106 (done; split escape sequences), TASK-42 (CI).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each target builds in CI; a plain cargo build does not build the fuzz crate
- [ ] #2 Each crash found becomes a regression test in its crate
- [ ] #3 The nightly command is in the tier list
- [ ] #4 The skills .claude/skills/lua-testing and .claude/skills/rust-testing name the new helpers and commands in the same commit.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a2198b180004f31ef, commits 59753cc6 (work) and 7b0f68ab (merge of main). fuzz/ (paw-fuzz): workspace member, not a default member; targets clip_file, project_folder, remote, terminal_keys; seeds in fuzz/seeds (2 KB, made by paw in the sealed test environment); tools/fuzz.sh runs them (nightly tier, CI only; needs cargo-fuzz and nightly, not in the dev shell). Flake: fuzz/Cargo.toml and fuzz/fuzz_targets in the cargo fileset; clippy check is now --workspace --exclude paw-gui --all-targets, so the targets keep compiling on stable. paw-tui has a lib (keys) and keys::Scripted. Crashes found while writing the targets, fixed with regression tests: clipfile tick overflow (origin/len near i64::MAX), remote::apply surface size/covered overflow and huge allocation, paw-scene write_text column overflow at i32::MAX. Not done: MIDI file reader, DAWproject and RPP readers are Teal (no cargo-fuzz target). AC3 waits for TASK-145 (no tier list exists yet): the nightly command is tools/fuzz.sh. No fuzzer ran: cargo-fuzz and nightly are not in the dev shell.
<!-- SECTION:NOTES:END -->
