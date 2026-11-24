---
id: TASK-98
title: 'Rust: paw-core interface (pub(crate)), workspace lints and rust-version'
status: Done
assignee: []
created_date: '2026-11-22T10:38:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - architecture
  - rust
  - quality
milestone: m-10
dependencies: []
priority: medium
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the interface of paw-core is what its callers use, and the compiler shows dead code. Finding F4 of the architecture review (backlog/docs/designs/architecture-review.md).

Today: paw-core/src/lib.rs has 37 pub mod, about 700 pub fn and 21 pub(crate) items; the binary uses about 12 items (Kernel and options, grid::{Grid, Cell}, remote::{apply, input_json}, rpc::Connection, tls::{identity, default_dir}, session::panic, clipfile::{text, decode}). No manifest has [lints] or rust-version.

Change: [workspace.lints] with rust.unreachable_pub = "warn" (and the clippy settings of TASK-20); rust-version in [workspace.package]; each module of paw-core pub(crate) except what other crates use, re-exported with pub use; delete the dead code that the compiler then finds.

Read first: the review, F4; Cargo.toml; crates/paw-core/src/lib.rs; .claude/skills/rust-skills (proj-pub-crate-internal, proj-msrv-declare, lint-*); TASK-20.
Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 paw-core exposes only the items that other crates use; cargo build has no unreachable_pub warning
- [x] #2 The workspace declares [workspace.lints] and rust-version; each crate inherits them
- [x] #3 Dead code that the change shows is deleted; all tests pass
- [x] #4 cargo clippy --workspace --all-targets reports 0 warnings (from TASK-20); the clippy settings are in [workspace.lints]
- [x] #5 The five fn hex go (from TASK-20): colors through paw_scene::color::Rgba FromStr, bytes through the hex crate. paw-gui is paused: leave its theme.rs:66 hex and write it in the report
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-aa02a5dbe7acbafee (on 0d19ed40, batch 17), commit 4c7f85d4. [workspace.lints] (unreachable_pub, browserpod check-cfg, clippy::undocumented_unsafe_blocks) and rust-version 1.95, inherited by every crate incl. paw-gui (warn only). paw-core: private modules except api, clipfile, clock, grid, media, model, remote, rpc, session, startuptime, stretch, sync, tls (used by paw-tui, fuzz, benches); only used items pub. Dead code deleted; test-only helpers #[cfg(test)]; bake helper lane kept with allow(dead_code, reason) (TASK-2/44/148 plan to use it). clippy --workspace --exclude paw-gui --all-targets: 0 warnings. fn hex gone except paw-gui theme.rs:66. Msg::Launch is Box<[Launch]>.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (4c7f85d4). [workspace.lints] and rust-version 1.95 in Cargo.toml, inherited by each crate; paw-core modules private except those that other crates use; dead code deleted; clippy 0 warnings (paw-gui excluded); fn hex gone except paw-gui theme.rs:66 (paw-gui is paused).
<!-- SECTION:FINAL_SUMMARY:END -->
