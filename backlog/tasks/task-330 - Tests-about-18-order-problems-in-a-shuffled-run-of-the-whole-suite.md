---
id: TASK-330
title: 'Tests: about 18 order problems in a shuffled run of the whole suite'
status: Done
assignee: []
created_date: '2026-11-23T20:00:00Z'
updated_date: '2026-11-24T03:24:00Z'
labels:
  - tests
milestone: m-12
dependencies:
  - TASK-291
priority: high
ordinal: 399000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After batch 18+19 (13488d86): the full suite passes, but tests/tools/suite.sh --shuffle 59639 fails 18 tests that pass in order: articulation rule mapping, snippet picker, project saved to a folder name, roll articulation K, articulations binding, undo file of a project changed outside paw, vinput ports and panel, templates track, clip_kinds unload, popover history, extension that waits and fails, pick marks/registers/messages, frames (check_stamps, listening meters, kept window and playhead, roll move key, audition meter at rest). TASK-291 fixed order within each extension's file; these cross files. Each cause is state that an earlier test leaves.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 suite.sh --shuffle 59639 and two other seeds pass
- [ ] #2 Each cause is named in the notes; fixes reset state in the test or the runner, not by order
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
PO 2026-11-23: moved from m-14 to m-12 (Better testing). TASK-149 waits for it. TASK-291 (waiting to merge) fixed the order problems inside the extensions' files; read its notes first, some of the 18 can be the same causes.

PO 2026-11-24: TASK-291 is on main (batch 20, 5041115e). Rebase onto main.

Built on branch worktree-agent-a1600ab1141a2820d (77f617bc, e9bc2b35; base 82f0aad0). 17 causes fixed at their source: watchdog far deadline (LONGEST_NAP, 2 Rust tests), runner clears messages before each test, T.until_meters_at_rest (manual clock, at most 5 s), plugin_state engine rest, keys_ux group name, articulations map id, custom_clips kind, piano roll providers in an owned registry (unload removes them), notation voice 1 on open, notation selection cleared on mode change, shada.use forgets the old file's times, seat close forgets its windows' buffers, placed playhead cleared on project.loaded, status cache keyed on opt.ascii, nest tap test uses T.advance, pointer tests put back note length, backend restored to the one that ran. Seeds 59639, 11, 22 pass apart from 2 tests that fail on clean 82f0aad0 too: 'pick: files opens projects and imports audio' (more than 600000 ms of the clock) and the apidoc check (stale generated file in that tree). Seen under load once: 'lenses: a one-shot server checks each render' waits 5000 ms of wall time, and the double-click test: both are timing risks for TASK-149. Joins batch 22.

pick: files clock overrun (batch 21): A1 added crates/paw-core/src/session/folder/testdata/chain/tracks/T1/..., deeper than files_depth 8; the walk ends with the note 'stopped at depth 8 (files_depth)' and the test waited for no note. Fix b859363b (tests/pick.lua waits while the note is 'reading…'). Risk: the test walks the repository; more entries than files_limit would stop it early (make it walk a fixture folder later).

On local main in batches 21+22 (4300ace4, 2026-11-24, not pushed). Full suite passed after two fixes (cab47711 a plugin is not work in flight; 4300ace4 the pick test waits for the walk); nix flake check passed.
<!-- SECTION:NOTES:END -->
