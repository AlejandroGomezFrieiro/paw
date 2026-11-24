---
id: TASK-281
title: >-
  Devices graph: the chain language (paw-chain crate, devices.chain on disk, the
  text buffer) (G7)
status: Done
assignee: []
created_date: '2026-11-23T11:58:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - devices-graph
milestone: m-16
dependencies:
  - TASK-279
documentation:
  - backlog/docs/designs/devices-graph.md
priority: high
ordinal: 343000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The owner wants the text form of a chain to be a proper language that a person and an agent can edit, and that is always testable. The design (section 10) makes it the file on disk, devices.chain in place of devices.json, with one Rust implementation used by the kernel, Lua, the command line, the language server and the MCP server. Each device kind needs a schema of its parameters so that the checks can find a wrong value or unit. Use a recommended parser crate (paw-crates.md).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A project saves each graph as tracks/<name>/devices.chain and loads it; devices.json is gone; plugin state stays in .state files
- [x] #2 The printer writes only values that differ from the default, and format of format is the same text
- [x] #3 Property tests: print then parse gives the same graph; parse of the formatted text gives the same graph as parse of the text
- [x] #4 A fuzz target for the parser in paw-fuzz, and golden files of the diagnostics of bad chains
- [ ] #5 :e paw://track/<n>/devices edits the graph as chain text; :w applies it as one undo step and says what changed; a text with an error changes nothing
- [x] #6 docs/reference/chain-language.md gives the grammar (EBNF) with an example of each rule, and a test parses each example
- [x] #7 A generic crate chain-syntax (no dependency on any paw crate, its own README and license, publishable) parses chain text with recovery (every error with line and column), prints, formats and checks it, and has no audio code
- [x] #8 Kinds, parameters, units and split kinds come from a host schema given as data (a documented JSON format, versioned); the language knows no host. paw writes its schema with paw chain schema (built-in, Lua and CLAP devices, split kinds); a second host such as REAPER can write its own
- [x] #9 A check in the suite and in nix flake check fails if a chain-* crate depends on a paw crate
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
Branch worktree-agent-ad8bc9b308ad8837e (base 0d19ed40, main merged). Commits 9f27d5dc (crate chain-syntax: parse with recovery, print, format, check against a JSON host schema; proptest, insta goldens of bad chains, fuzz target chain_text, tools/chaindeps.lua + flake check chaindeps, paw chain schema in paw-core chain_schema.rs + paw-tui), db0acf49 (docs/reference/chain-language.md and chain-schema.md with tested examples, crate README, docs index), 303d0c54 (merge main). Parser crate: winnow. Deferred to after TASK-279: AC1 and AC5 (devices.chain on disk, paw://track/<n>/devices buffer, :w as one undo step). Orchestrator runs after build: cargo nextest run -p chain-syntax -p paw-core -E 'test(chain)'; cargo test --doc -p chain-syntax; cargo nextest run -p paw-tui --test chain.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Lands as built in batch 19. Keep winnow (plan C1). Chain language 2 (a document is the graph of one part) is bundle CL2.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main as built (9f27d5dc, db0acf49). The generic crate chain-syntax on winnow: parse with recovery, print, format, check against a JSON host schema; property tests, insta goldens, fuzz target chain_text; tools/chaindeps.lua in the flake; paw chain schema; chain-language.md and chain-schema.md with tested examples. AC 1 and AC 5 (devices.chain on disk, the paw://track/<n>/devices buffer, :w as one undo step) moved to bundle MX (TASK-312): the roadmap says devices.chain waits for the part graph.
<!-- SECTION:FINAL_SUMMARY:END -->
