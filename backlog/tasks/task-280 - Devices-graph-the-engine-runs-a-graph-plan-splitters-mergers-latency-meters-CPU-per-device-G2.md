---
id: TASK-280
title: >-
  Devices graph: the engine runs a graph plan (splitters, mergers, latency,
  meters, CPU per device) (G2)
status: Done
assignee: []
created_date: '2026-11-23T11:57:00Z'
updated_date: '2026-11-24T03:24:00Z'
labels:
  - devices-graph
  - bundle
milestone: m-16
dependencies:
  - TASK-279
  - TASK-301
references:
  - architecture/decisions/0011-devices-graph-and-chain-language.md
  - architecture/decisions/0024-one-project-graph.md
  - architecture/decisions/0027-mix-as-graph-nodes.md
  - backlog/docs/designs/architecture-plan.md
documentation:
  - backlog/docs/designs/devices-graph.md
priority: high
ordinal: 342000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The audio thread must run splits with no lock, no allocation and no wait. The design compiles the tree into a flat plan of operations on buffers that the plan owns, sent in one message (Msg::SetGraph). Design section 4.4.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A serial graph is equal to the bit to the chain of today (a null test)
- [ ] #2 A band split with nothing in it sums flat (LR4), a mid/side split with nothing in it is the identity, and a layer of N equal branches has the expected gain
- [ ] #3 Latency in one branch is compensated, so all branches arrive at the merge together, and the track reports the total latency
- [ ] #4 A plan swap and the processing of a plan do not allocate (the check for no allocation)
- [ ] #5 A topology change while the song plays fades out and in over 5 ms
- [ ] #6 The engine measures a peak meter for each node and branch, and the CPU time of each device, and the kernel can read them
- [ ] #7 Freeze and render use the plan
- [ ] #8 The plan is of a Chain (the inserts of a strip). The compiler resolves KindId<SplitFamily> through Kinds<SplitFamily, SplitImpl>; an absent kind compiles as its first branch in series with a diagnostic
- [ ] #9 GraphPlan keeps its buffers in one Box<[f32]>, its indices are Buf, and only compile makes one. Msg::SetGraph names a ProcessorSlot, not a track. The order of slots does not change in this ticket (MX gives it from compose)
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
PO 2026-11-23 (plan V2 bundles): Bundle G2 (architecture-plan.md V2.13, V2.15). Starts after A1 (TASK-301). Engine only: it can run beside W1. MX builds on its ProcessorSlot.

From A1: G2 must make an absent split kind play its first branch (SplitFamily ABSENT rule is PassThrough; check lets it pass, validate gives AbsentKind). Today the engine plays every chain in series.

Built on branch worktree-agent-a8f0b4e6234330556, commit 83e4ecb3 (base 82f0aad0): sync compiles each chain into a GraphPlan (paw_engine::plan, one Box<[f32]> arena, Buf indices), Msg::SetGraph { slot: ProcessorSlot, plan }, splits/branches/mix/gain/latency play, 5 ms fade on a new shape, same shape keeps state, absent kind plays its first branch with a warning, meters per node/branch and CPU per device (Rust readers only). Tests: null tests (serial = old chain bits), band sum flat, mid/side identity, latency alignment, no_alloc with swaps and fades, absent kind. Orchestrator decision: the absent-kind warning stays in the document warnings until G3 shows it in the devices view. Joins batch 22. Follow-ups TASK-336..339.

On local main in batches 21+22 (4300ace4, 2026-11-24, not pushed). Full suite passed after two fixes (cab47711 a plugin is not work in flight; 4300ace4 the pick test waits for the walk); nix flake check passed.
<!-- SECTION:NOTES:END -->
