---
id: TASK-214
title: >-
  Freeze: render in the background through the bake scheduler, and a key with
  the plugins' versions and state
status: To Do
assignee: []
created_date: '2026-11-23T06:36:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - freeze
  - media
  - bundle
milestone: m-5
dependencies:
  - TASK-10.1
references:
  - architecture/decisions/0025-render-with-provenance.md
  - backlog/docs/designs/architecture-plan.md
priority: low
ordinal: 242000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-7.13 and TASK-77.9 (their agents named these gaps). The freeze of a track and of a block renders in the kernel's turn: the user waits, and the block or track does not play live while the bake runs, as media.md 2.9 wants. The key that says whether a freeze is stale is made in Lua (runtime/lua/paw/bake_state.tl): it does not hold the plugins' names, versions or saved state, nor the audio edits (only their count). The design key is BLAKE3 over the canonical text (nest.md 4.4, media.md 2.7).

What to build, when media M4+ (TASK-10) gives Provenance and the bake scheduler:
- :freeze starts a bake through the scheduler; the track or block plays live until the file is ready, then plays the file.
- The key moves to the kernel's input_key, with the plugin names, versions and a hash of their state, and the edit list.

Read first: backlog/docs/designs/media.md 2.7 to 2.9; backlog/docs/designs/nest.md 4.4; runtime/lua/paw/bake_state.tl, freeze_block.tl, freeze.lua; crates/paw-core/src/freeze.rs and bake/; the notes of TASK-77.9 and TASK-7.13.

Size: M. It waits for the bake scheduler of TASK-10.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test: while a freeze bakes, the track plays live; when the bake ends, it plays the file, without a wait in the test (a step or an event)
- [ ] #2 Test: a change of a plugin's saved state, with the same parameters, makes the freeze stale
- [ ] #3 bake_state.tl's key is gone or only reads the kernel's key; freezing.md is true; Vale reports 0 alerts
- [ ] #4 No new model field for freeze: meta.frozen stays until RD makes freeze a render with replace
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
Orchestrator 2026-11-23: stays in m-5 with TASK-10; the freeze works today, this removes the wait and makes the stale check exact.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): FZ: build only the bake job and its key. No new model field for freeze: meta.frozen stays until RD makes freeze a render with replace (ADR 0025). Depends on MD4 (the bake scheduler).

PO 2026-11-23 (plan V2 bundles): Bundle FZ. Depends on MD4 (TASK-10.1), the bake scheduler. RD (TASK-316) then makes freeze a render with replace.
<!-- SECTION:NOTES:END -->
