---
id: TASK-303
title: >-
  Chain language 2: a document is the graph of one part, with typed ports,
  producers and store wires (CL2)
status: Done
assignee: []
created_date: '2026-11-23T16:01:00Z'
updated_date: '2026-11-24T03:24:00Z'
labels:
  - devices-graph
  - chain-language
  - bundle
milestone: m-16
dependencies: []
references:
  - architecture/decisions/0012-generic-chain-language.md
  - architecture/decisions/0024-one-project-graph.md
  - architecture/decisions/0027-mix-as-graph-nodes.md
  - architecture/decisions/0028-typed-lanes-and-converters.md
  - backlog/docs/designs/architecture-plan.md
priority: medium
ordinal: 365000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle CL2 of the architecture plan, version 2 (backlog/docs/designs/architecture-plan.md V2.13 and V2.15; containers.md 7.3 to 7.6 where version 2 does not replace it).

A document of chain language 2 is the graph of one part. Header: chain 2 "Violin I". Top-level node lines (strip, bus, send, master, vca, producer, io) with their parameters. A strip holds its inserts as an indented chain of version 1. Wires: a -> b (live) and a => lane (store). Outside ends: @"Strings/Violin I/Notes". Ports and stream types with their properties come from the host schema (chain_schema: 2). The produce block of version 1 is gone: a producer is a node, and its sink is a store wire.

The crates chain-syntax and chain-lsp stay free of paw. paw writes no part graph to devices.chain in this bundle: MX does that (V2.14).

Read first: the skill .claude/skills/architecture (after batch 19 it is on main), architecture/08-concepts.md and 13-roadmap.md, the ADRs in the references, and backlog/docs/designs/architecture-plan.md (the sections that this ticket names). An Opus agent does the whole bundle in one branch, with its tests and docs in the same commits. Also the notes of TASK-281 and TASK-287, and docs/reference/chain-language.md and chain-schema.md.

Size: M. It can start when TASK-287 is on main (batch 19). Merge it after A1: both change chain_schema.rs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Grammar version 2: node lines strip, bus, send, master, vca, producer and io with fields; a strip holds its inserts as an indented chain of version 1; wires a -> b and a => <lane>; outside ends @"path/to/lane". A reader of version 2 reads a document of version 1 as the inserts of one strip
- [ ] #2 chain_schema: 2 has streams with props (a ParamSchema), time and records, and kinds with ports (port, stream, props, main, out), tier and converts
- [ ] #3 The diagnostics E213 to E218 and W302 of containers.md 7.3, with E213 for a gap of type that names the missing property; each has a golden diagnostic and a test that does not fire
- [ ] #4 Property tests: print then parse with node lines, store wires and outside ends; the fuzz target covers the new tokens
- [ ] #5 paw: chain_schema.rs writes midi, audio and curve and the ports of the built-in devices; paw chain context <track> writes the outside lanes and nodes as JSON
- [ ] #6 chain check and chain-lsp take the optional host context (JSON, empty by default) if TASK-287 did not add it; no lint, completion or hover assumes that each port is audio; chain-lsp completes outside ends from the context
- [ ] #7 docs/reference/chain-language.md and chain-schema.md are true; each example parses (a test); Vale reports 0 alerts
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
PO 2026-11-23 (after batch 18+19): the server and the generic crate of TASK-287 are on main, so this bundle no longer waits for TASK-287; TASK-287's lints wait for this bundle instead. Merge after A1 (TASK-301): both change chain_schema.rs. AC 6 applies: TASK-287 did not add the host context.

Commit 05b4a95e (same branch): grammar, schema v2, E213-E218 and W302, proptests and fuzz seed, chain-lsp context (chainContext, chain/context), paw's schema v2 (streams, roles, default_ports). AC 5 half: 'paw chain context <track>' not built (needs kernel and paw-tui args after A1). Also formats chain-syntax with rustfmt. Proposed ADR 0037 (details). Merge after A1; keep CL2's streams/nodes/default_ports in chain_schema.rs.

ADR 0037 accepted by the owner 2026-11-23.

PO 2026-11-24: built, waits to merge (batch 21 or 22); status In Progress until it is on main.

On local main in batches 21+22 (4300ace4, 2026-11-24, not pushed). Full suite passed after two fixes (cab47711 a plugin is not work in flight; 4300ace4 the pick test waits for the walk); nix flake check passed.
<!-- SECTION:NOTES:END -->
