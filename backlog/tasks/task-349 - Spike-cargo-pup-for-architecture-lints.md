---
id: TASK-349
title: 'Spike: cargo-pup for architecture lints'
status: Done
assignee: []
created_date: '2026-11-24T10:48:00Z'
updated_date: '2026-11-24T10:57:00Z'
labels:
  - agent:worker
  - quality
  - spike
dependencies: []
priority: high
ordinal: 418000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24: try cargo-pup (Datadog) for architecture lints. cargo-pup is a rustc driver: its README pins nightly-2025-07-25 with rust-src, rustc-dev, llvm-tools-preview; paw builds on stable rustc 1.95 (nixpkgs), edition 2024. Time box: one agent session. Steps: (1) get the pinned nightly into a separate flake output or a nix shell (rust-overlay or fenix input), never into the default dev shell yet; (2) build cargo_pup with it; (3) run cargo pup print-modules and check on paw-core and paw-engine: does our code compile under that nightly (features stabilised after it)? (4) if yes, write the layer rules we have today as pup rules (model/ must not depend on sync, session, api, kernel; chain-syntax and chain-lsp must not depend on paw crates, as tools/chaindeps.lua checks) with the builder API (cargo_pup_lint_config as a dev-dependency, assert_lints in a test) or pup.ron, and show one rule failing on a planted violation; (5) report: works or not, build time, what it would replace (tools/chaindeps.lua, the ast-grep layer rule of TASK-348), and the cost of a second toolchain in the flake.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A report with a go or no-go and the evidence; no change to the default dev shell or flake checks unless go
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Each acceptance criterion is met, and the notes give its evidence
- [ ] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [ ] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [ ] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [ ] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [ ] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [ ] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [ ] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Spike result 2026-11-24: NO-GO for now. cargo_pup 0.1.9 pins nightly-2026-01-22; paw compiles under it; pup.ron rules for model/ layering and chain crates work and a planted use crate::sync fails (exit 101). But: RestrictImports sees only use items (an inline crate::sync::x path passes), it needs a rustup shim and SYSROOT on Nix, a second 1.5 GB toolchain plus 700 MB build dir, warm run 18 s, and tools/layers.lua + chaindeps.lua already cover both rules. Revisit for rules layers.lua cannot express (trait impl naming, pub limits). The ron is in the spike's notes, not committed.
<!-- SECTION:NOTES:END -->
