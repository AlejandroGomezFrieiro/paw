---
id: TASK-282
title: >-
  Devices graph: the view (graph and inspector windows, flow layout with wrap
  and auto-fold, racks, breadcrumbs, header) (G3)
status: Done
assignee: []
created_date: '2026-11-23T11:58:00Z'
updated_date: '2026-11-24T09:58:00Z'
labels:
  - devices-graph
  - bundle
  - agent:builder
milestone: m-16
dependencies:
  - TASK-279
  - TASK-301
references:
  - architecture/decisions/0011-devices-graph-and-chain-language.md
  - architecture/decisions/0003-one-view-two-frontends.md
  - backlog/docs/designs/architecture-plan.md
documentation:
  - backlog/docs/designs/devices-graph.md
priority: high
ordinal: 344000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The device panel shows one device at a time. The graph view must show the shape of a chain of 20 devices in a few rows, at 80 and 120 columns, in one Lua view for both frontends. The evaluation with three metal chains (design section 9.2) showed that it needs wrap, folds by default and racks. The inspector becomes its own window (design section 5.6). Design sections 6 and 9.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 views/devices.tl draws the flow layout: serial cards, splits with rails and branch heads, rack frames, a folded card with a summary, and the outline layout under 72 columns
- [ ] #2 The top level wraps with ↩ and ↪; a container off the cursor's path that does not fit folds itself; containers start folded and the path to the cursor opens
- [ ] #3 A header with devices, containers, latency, CPU and keys; a breadcrumb line with the path of the cursor; chips for solo, bypass, variant and pin
- [ ] #4 The inspector is a window under the graph: the device panel of today narrowed to the node under the graph cursor, with the macro face on a container
- [ ] #5 Golden screens of the three metal chains of the design, folded and open, at 80 and 120 columns
- [ ] #6 The same scene draws in the window (paw-scene roles); the window itself is not built or tested while it is paused
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
PO 2026-11-23 (plan V2 bundles): Bundle G3. The view edits the inserts of one strip through paw.chain.of (A1, TASK-301). The graph view of a part is GV (TASK-318). Merge it before W1 or start it after W1: W1 renames the words in views/devices.tl.

Wave 23 (2026-11-24), base 9cecbfdc (batches 20-22 + W1).

Agent finished 2026-11-24 (70462fa7, 9f4916ff): ACs 1-6 done except the variant chip (no variant model). Follow-ups for G4: variant chip; inspector modulators and gm/gM; 'below 24 rows the inspector closes'; \p pins the graph, not the inspector. Owner questions: keys of <Space>dd go to the inspector (parity, recommended) or the graph; should the graph window fit its height to content.

On local main (795c22ca, 2026-11-24, not pushed). Review fixes done; merge-check green: lints, clippy 0, nextest 676/676, suite words incl. golden all passed.
<!-- SECTION:NOTES:END -->
