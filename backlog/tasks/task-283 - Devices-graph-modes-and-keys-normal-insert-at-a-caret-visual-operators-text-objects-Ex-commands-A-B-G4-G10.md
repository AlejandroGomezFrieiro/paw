---
id: TASK-283
title: >-
  Devices graph: modes and keys (normal, insert at a caret, visual, operators,
  text objects, Ex commands, A/B) (G4, G10)
status: To Do
assignee: []
created_date: '2026-11-23T11:58:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-16
dependencies:
  - TASK-282
references:
  - architecture/decisions/0011-devices-graph-and-chain-language.md
  - backlog/docs/designs/architecture-plan.md
documentation:
  - backlog/docs/designs/devices-graph.md
priority: high
ordinal: 345000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The grammar of the graph must follow Vim and the key rule, with a clear separation of the five modes of paw: normal moves and changes values, insert adds nodes at a caret, visual selects, the operators take motions and text objects. The owner dropped H and L as node moves: << >> and < > move a node in signal order. Design sections 5 and 5.6, and 9.8 for the changes after the metal chains. A/B (\b, \a, =) goes here because it is mostly keys.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The motions, text objects (in ib ab is as ir ar im ie), operators (d y c > < = gc gs gm gM zf zn) and Ex commands of section 5 work, each change is one undo step and says what it did
- [ ] #2 i starts insert mode with a caret; the insert keys add nodes, paw.opt.graph_insertkeys and paw.insert.add with view = devices change them, and all of one insert is one undo step
- [ ] #3 a adds one device from the picker; o O add a branch and start insert mode; c cuts and starts insert mode with the picker; cc chooses a preset
- [ ] #4 v V Ctrl-v select nodes, branches and blocks; the status line and the title show each mode as section 5.6 says
- [ ] #5 Tests with real keys for each operator and mode; the key rule constitution passes; key-rule.md and the reference page of the view change in the same commit
- [ ] #6 \s \S solo a branch, \b bypasses the chain and keeps the state of each node, \a flips variants, = matches the gain
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
PO 2026-11-23 (plan V2 bundles): Bundle G4. The stack panel of TASK-75.4 (M4) reuses the inspector rows: keep device_rows as a public function of the view. Starts after W1.

From G3 (2026-11-24): \p pins the graph, not the inspector, to a node; decide here. The design rule 'below 24 rows the inspector closes' is not done yet: take it here.

From the G3 review (2026-11-24): map + - on a device node in the graph (key rule); the devices header CPU figure is sampled per draw (move to a timer or the kernel); inspector rows() and devices node() write state during render; the inspector reads the module graph, not a window seat (two pinned devices windows).
<!-- SECTION:NOTES:END -->
