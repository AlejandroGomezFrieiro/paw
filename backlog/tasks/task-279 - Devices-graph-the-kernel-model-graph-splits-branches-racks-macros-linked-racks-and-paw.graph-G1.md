---
id: TASK-279
title: >-
  Devices graph: the kernel model (graph, splits, branches, racks, macros,
  linked racks) and paw.graph (G1)
status: Done
assignee: []
created_date: '2026-11-23T11:57:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - devices-graph
milestone: m-16
dependencies:
  - TASK-278
documentation:
  - backlog/docs/designs/devices-graph.md
priority: high
ordinal: 341000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Track.devices is a flat list today. The graph needs a tree beside it: splits of each kind, branches with gain, pan, mute and solo, racks (a split of kind chain with one branch), macros on each container, and linked rack definitions with overrides per instance. Many places read Track.devices, so the flat list stays and the graph names its devices by id. Design sections 4 and 9.4 to 9.5.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A Track has an optional graph; a track with no graph plays its devices in series as today
- [x] #2 Graph::validate refuses a tap to a later node, a loop, the wrong number of branches for a kind and band crossovers out of order, each with a clear message
- [x] #3 Each edit of the graph (wrap, unwrap, add a branch, move a node, set a value of a split or branch) is one undo step and says what it did
- [x] #4 A linked rack: a change of its definition reaches each instance, and an override on one instance stays
- [x] #5 The Lua API paw.graph (Teal) reads the tree and makes each edit; the API reference comes from its doc comments
- [x] #6 Property tests of the model, as in crates/*/tests
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
G1 kernel model on branch worktree-agent-a5603cc7cf5901939, commit 3ac0c8b3 (base 0d19ed40). Track.graph: Option<Arc<Graph>> beside the flat devices; no graph = serial. model/graph.rs (+kinds.rs registry of open Word kinds over a Builtin enum), model/linked.rs (generic Linked<D,O> + Keyed), model/racks.rs (RackLink = Linked<Id, RackOwn>, Project.racks -> racks.json), session/document/graph.rs (edits, one undo step each), api/graph.rs, runtime/lua/paw/graph.tl. Devices are kept in graph signal order, so the engine plays a graph in series until TASK-280. Mapping point for TASK-281: model::graph::{Graph,Split,Branch,Node,Tap,Macro,Link,Zone}, SplitKinds, Graph::validate, Track.graph, Project.racks. Pending: owner direction of 2026-11-23 (graph edits as pure fns on Graph, owner handle, NodeId/DeviceId/ParamKey newtypes, kinds resolved at compile), cost given to coordinator.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Lands as built in batch 19. Its alignment to version 2 (Graph to Chain, paw.graph to paw.chain, owner-free, typed ids, kinds core) is bundle A1 (architecture-plan.md V2.13).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main as built (3ac0c8b3). Track.graph (no graph plays in series), Graph::validate, edits as one undo step each, linked racks (Linked, Project.racks, racks.json), paw.graph in Teal with generated docs, property tests in model/graph/props.rs. The version 2 shape (Chain, paw.chain, owner-free pure edits, typed ids, kinds core) is bundle A1, TASK-301.
<!-- SECTION:FINAL_SUMMARY:END -->
