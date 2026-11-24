---
id: TASK-352
title: >-
  Dev tools: hooks, formatters and lints as configuration (git-hooks.nix,
  treefmt-nix, ast-grep for Lua)
status: To Do
assignee: []
created_date: '2026-11-24T10:53:00Z'
updated_date: '2026-11-24T11:01:00Z'
labels:
  - agent:builder
  - quality
  - foundation
dependencies: []
priority: high
ordinal: 421000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24: set up the dev tools now. (1) git-hooks.nix (cachix) defines the pre-commit hooks once in flake.nix; the same list runs as a flake check; .githooks/pre-commit and core.hooksPath go (the hook still runs in each worktree). (2) treefmt-nix runs rustfmt, StyLua and nixfmt as one formatter; one commit formats the whole tree (land it when few branches are in flight: say so in the report), then the format check fails; tools/fmtcheck.sh goes. (3) ast-grep, after TASK-348 set it up for Rust: port tools/partlint.lua, zoomlint.lua, gridlint.lua and chaindeps.lua (if TASK-349 does not take chaindeps) to ast-grep rules with ast-grep tests; Lua is built in; for Teal try a custom language with tree-sitter-teal (experimental is fine) and keep the Lua script for Teal only if that fails; the allow-lists become rule ignores or #[expect]-like comments with a reason. (4) tools/ste-check.lua: compare with the Vale STE rules in .vale.ini/styles; delete what Vale covers, move the rest into Vale rules. Keep tools/layers.lua, testlint.lua and apidoc.lua. Base: after TASK-348 merges.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One list of hooks in flake.nix runs as pre-commit and in nix flake check
- [ ] #2 treefmt is the only formatter entry; the whole tree is formatted; the check fails on an unformatted file
- [ ] #3 partlint, zoomlint and gridlint (and chaindeps unless cargo-pup took it) are ast-grep rules with tests; their Lua scripts are gone; the allow-lists keep their reasons
- [ ] #4 ste-check.lua is gone or holds only what Vale cannot express, with the reason
- [ ] #5 AGENTS.md, CLAUDE.md pointers, the skills paw-code part 7 and the docs name the new commands; no stale name of a removed tool (give the search)
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
From the review of TASK-348: the ast-grep rules have gaps to fix while porting: model-names-higher-layer misses nested groups (use crate::{model::{A,B}, sync::S}), super::super:: paths and macro paths, and fires on crate::{ids::api}; constant-fn misses string/None/'1.' bodies and fns nested in impl methods, and fires on trait default methods; one-value-helper ^is_(zero|one|...) needs (_|$) to skip is_zero_crossing. Also: 11 #[allow] remain under a module expect(clippy::allow_attributes) (shm.rs:290, bake/key.rs, store.rs, scheduler.rs, bake/mod.rs, api/midi.rs:54,57 without reason, api/mod.rs, engine midi.rs, backend.rs, midi_out.rs, paw-listen lib.rs): make them expect with a reason. And the generic reason 'debt: pay down' replaced specific ones (chain-syntax 'running work on the chain language', paw-core api): restore the specific reasons.
<!-- SECTION:NOTES:END -->
