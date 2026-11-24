---
id: TASK-312
title: >-
  The mix as nodes: the part graph with strips, buses, sends, VCA and master;
  compose; arm on lanes; devices.chain (MX)
status: To Do
assignee: []
created_date: '2026-11-23T16:02:00Z'
updated_date: '2026-11-24T14:20:00Z'
labels:
  - agent:builder
  - architecture
  - mix
  - bundle
milestone: m-17
dependencies:
  - TASK-309
  - TASK-280
  - TASK-303
references:
  - architecture/decisions/0027-mix-as-graph-nodes.md
  - architecture/decisions/0024-one-project-graph.md
  - architecture/decisions/0032-project-folder-of-parts-and-lanes.md
  - architecture/decisions/0011-devices-graph-and-chain-language.md
priority: high
ordinal: 379000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle MX of backlog/docs/designs/architecture-plan.md V2.2, V2.4, V2.5 and V2.7 step 4 (phase 4). The highest risk of the plan. The strip fields of a part move to a Strip node in Part.graph; output, sends, VCAs, groups and the master become nodes and wires (ADR 0027). compose makes the project graph from the part graphs, incremental by Arc::ptr_eq (ADR 0024, V2.16 P5); the planner gives each ProcessorSlot its plan (TASK-280). Arm moves to the lanes that record. devices.json becomes devices.chain in chain language 2 (CL2). MX runs alone in sync/ and with no other bundle on the mixer view. Tests: the null test of renders on the test corpus (same bits before and after), and a compose property test (the union of the part graphs is the graph of today's routing). Solo is state of strips and buses; solo on a lane solos the strips that it feeds (V2.16 P2).

This ticket has a title and a description only. The product owner adds the acceptance criteria when its phase starts, from backlog/docs/designs/architecture-plan.md and the ADRs in the references. One Opus agent does the bundle.
<!-- SECTION:DESCRIPTION:END -->

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
PO 2026-11-23 (after batch 18+19): TASK-281 AC 1 and AC 5 moved here: a project saves the graph of a part as devices.chain and loads it (devices.json goes; plugin state stays in .state files), and :e paw://part/<n>/devices edits it as chain text; :w applies it as one undo step and says what changed; a text with an error changes nothing. Add them to the criteria when this phase starts.

From A1: Track.chain is serialized with the key 'graph' in track.json; rename the key to 'chain' with the file layout change of MX.
<!-- SECTION:NOTES:END -->
