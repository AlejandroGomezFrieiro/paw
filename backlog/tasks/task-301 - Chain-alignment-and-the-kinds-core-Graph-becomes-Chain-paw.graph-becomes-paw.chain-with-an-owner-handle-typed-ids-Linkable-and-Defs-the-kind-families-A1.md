---
id: TASK-301
title: >-
  Chain alignment and the kinds core: Graph becomes Chain, paw.graph becomes
  paw.chain with an owner handle, typed ids, Linkable and Defs, the kind
  families (A1)
status: Done
assignee: []
created_date: '2026-11-23T16:01:00Z'
updated_date: '2026-11-24T03:24:00Z'
labels:
  - architecture
  - devices-graph
  - bundle
milestone: m-16
dependencies:
  - TASK-279
  - TASK-281
references:
  - architecture/decisions/0017-architecture-plan-as-target.md
  - architecture/decisions/0011-devices-graph-and-chain-language.md
  - architecture/decisions/0012-generic-chain-language.md
  - architecture/decisions/0024-one-project-graph.md
  - backlog/docs/designs/architecture-plan.md
priority: high
ordinal: 363000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle A1 of the architecture plan, version 2 (backlog/docs/designs/architecture-plan.md V2.13 and V2.15; section 6.2 gives the base criteria).

TASK-279 lands as built in batch 19: Track.graph, Linked<D, O> with string keys, Project.racks, split kinds as Word, and the edits in the session. This bundle gives it the version 2 shape one time, before TASK-280 (G2), TASK-282 (G3) and TASK-75.1 (M1) build on it:
- The built type Graph becomes Chain: the inserts of a strip and the body of a rack. The word "graph" is free for the part graph (ADR 0024).
- paw.graph becomes paw.chain, with paw.chain.of(owner).
- The chain model is owner-free. Each edit is a pure function.
- Typed ids, Linkable and Defs.
- The kinds core: Kinds<F, S> and the families of V2.3, which A2, M1, B3 and TASK-97 use.

Track.graph stays on the track until MX moves it to Strip.inserts. The file stays devices.json until MX. Do not change the engine (TASK-280 does that).

Read first: the skill .claude/skills/architecture (after batch 19 it is on main), architecture/08-concepts.md and 13-roadmap.md, the ADRs in the references, and backlog/docs/designs/architecture-plan.md (the sections that this ticket names). An Opus agent does the whole bundle in one branch, with its tests and docs in the same commits. Also rust-architecture.md parts 2, 3.2, 6.2 and 10, and the notes of TASK-279 and TASK-281.

Size: M. If it runs over, commit the kinds core (AC 1) first, so that M1 can start from it.
Merge order: A1 first. TASK-95.1 (P95) and the new chain language (CL2) merge after it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 model/kinds.rs has Family (sealed), Absent, KindId<F> (dot-joined words, FromStr, serde as text), Version, Stored<F>, Loaded<F, T>, Owner and Kinds<F, S> with put, get, remove, unload, owned_by and a shadow stack. The families of architecture-plan.md V2.3 exist as types; StreamFamily has no entries yet. A Rust test puts two owners on one key, unloads the top one and gets the lower one back
- [ ] #2 The built type Graph is Chain (model/chain.rs, model/chain/edit.rs) and GraphError is ChainError. No Rust or Lua name uses the word graph for the inserts of a strip
- [ ] #3 Split kinds are KindId<SplitFamily>, and the registry is Kinds<SplitFamily, SplitImpl>. An unknown split kind loads, saves the same bytes, and Chain::validate gives ChainError::AbsentKind
- [ ] #4 model/chain.rs and its submodules name no Track and no track id. Each edit is a pure fn(&Chain, ..) -> Result<Chain, ChainError> in model/chain/edit.rs. The session only finds the owner, calls the function, makes one undo step and gives the message. The tests of TASK-279 pass with no change of keys
- [ ] #5 OwnerRef is an enum with one variant Track(TrackId); W1 and MX add the other variants
- [ ] #6 DeviceId, NodeId, ParamKey and DefId<D> replace Id in the chain, the racks and the links. devices.json and racks.json keep their bytes (a round trip test)
- [ ] #7 Linked<D: Linkable> { of: DefId<D>, overrides: D::Overrides }, Defs<D> and Keyed<K: Ord> with the follow rule. RackDef: Linkable with RackOwn { ids, values: Keyed<ValueKey> }; ValueKey is an enum whose text form is the chain reference (#5.ratio). Project.racks is Defs<RackDef>. The linked rack tests pass
- [ ] #8 No meta on a split. A test that set split meta is removed or moves to a declared key
- [ ] #9 paw.graph is paw.chain. paw.chain.of(owner) gives a handle ({track = id} until W1), and each function of paw.chain takes it. The Teal types and docs/reference/api.md come from the doc comments (tools/apidoc.lua)
- [ ] #10 The mapping of TASK-281 (chain_schema.rs and the lowering) uses the new types, and its tests pass
- [ ] #11 Docs: docs/reference/project-files.md and the devices graph and chain pages are true; the extension skill names paw.chain; Vale reports 0 alerts
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
Done on branch worktree-agent-a2b6c50f80e5d9e24 in 3b93be0d (kinds core) and 9a0bfef2 (Graph → Chain, paw.graph → paw.chain with paw.chain.of(owner) handle). Lua tests (tests/chain.lua) need a build. ValueKey keeps the file form and shows the chain reference. Track.chain keeps the serde key 'graph' until MX (orchestrator decision). Follow-ups: unload of extension split kinds (new ticket), first-branch play of an absent kind (note on TASK-280). Architecture edits staged in scratchpad/pending-arch/A1.md. Merges in batch 21 with CL2 (keep CL2's streams/nodes/default_ports in chain_schema.rs).

PO 2026-11-24: built, waits to merge (batch 21 or 22); status In Progress until it is on main.

On local main in batches 21+22 (4300ace4, 2026-11-24, not pushed). Full suite passed after two fixes (cab47711 a plugin is not work in flight; 4300ace4 the pick test waits for the walk); nix flake check passed.
<!-- SECTION:NOTES:END -->
