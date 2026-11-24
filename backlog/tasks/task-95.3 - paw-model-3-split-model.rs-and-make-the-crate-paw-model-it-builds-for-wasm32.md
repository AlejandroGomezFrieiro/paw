---
id: TASK-95.3
title: 'paw-model 3: split model.rs and make the crate paw-model; it builds for wasm32'
status: To Do
assignee: []
created_date: '2026-11-23T07:03:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-10
dependencies:
  - TASK-95.1
  - TASK-306
  - TASK-312
parent_task_id: TASK-95
priority: medium
ordinal: 265000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Parts 3 and 4 of TASK-95, after the blockers (TASK-95.1, TASK-95.2) are on main.

What to build:
- Split crates/paw-core/src/model.rs into model/project.rs, track.rs, clip.rs, lane.rs and check.rs.
- Make the crate paw-model: model, history, attr_map, clipfile, edits, events, Document, and the layout and the read of session/folder.rs (the commit stays in paw-core). It makes no call to the operating system.
- CI builds paw-model for wasm32-unknown-unknown (a check in the flake).

Read first: TASK-95 (description and notes), backlog/docs/designs/architecture-review.md F1, backlog/docs/designs/web.md (blockers by crate), TASK-51, .claude/skills/rust-skills and paw-crates.md.

Do not touch: the Lua API (paw.api stays the same); paw-gui (paused).

Size: M to L. Split it again at the start when the move is more than one day.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 paw-model builds with cargo check --target wasm32-unknown-unknown, and nix flake check runs that check
- [ ] #2 Rust tests of edits and undo run in paw-model without an engine
- [ ] #3 The Lua suite and the Rust tests pass with no change of behavior
- [ ] #4 Docs, skills and AGENTS.md that name the moved files are searched and fixed; Vale reports 0 alerts
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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): PM3: split model.rs after A2 and MX, which move many model fields (architecture-plan.md V2.14). Unblocked by: A2 and MX.

Remaining blockers of paw-model after P95: paw_engine::MAX_PAIRS in document/devices.rs; sync::ModelEvent; the engine types in attr_map and edits: ClipSet, MidiEv, Switch, AudioData, db_to_gain, midi_out::on_channel.
<!-- SECTION:NOTES:END -->
