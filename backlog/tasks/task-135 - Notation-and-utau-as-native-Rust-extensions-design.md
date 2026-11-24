---
id: TASK-135
title: Notation and utau as native Rust extensions (design)
status: To Do
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - architecture
  - extensions
  - lua-review
milestone: m-11
dependencies:
  - TASK-96
priority: low
ordinal: 147000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-11-22: notation and utau should move to Rust as native extensions later, not to Teal. Design how. Constraint from the owner's decision on the Rust review (Q6): paw never loads Rust libraries into the kernel. So compare a separate process that speaks a protocol (as the utau engine does now), a WebAssembly extension (TASK-2), and a native module in the Lua host process if that is not the kernel. Say what stays in Lua (keys, commands, views) and what moves (the music logic, the data work). MIDI stays the truth: the extension keeps its data in meta.

Read first: backlog/docs/designs/architecture-review-lua.md (L10), backlog/docs/designs/architecture-review.md (E1, E6 and the owner decisions), the READMEs of extensions/notation and extensions/utau.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A design note in backlog/docs/designs/ compares the three ways, with measurements where they decide
- [ ] #2 The note gives the order of the move and the tickets for it
- [ ] #3 The owner approves the note before any code moves
- [ ] #4 The note compares four ways: a separate process, WebAssembly, a native module outside the kernel, a Cargo feature of the paw binary
- [ ] #5 The note measures the calls that cross the boundary on a key and on a frame for each extension (count and size), on the bench project
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
Owner, 2026-11-22: compare a fourth way too: the Rust code built into the paw binary as an optional Cargo feature (same speed as in-process, no ABI problem, not crash safe, Nix builds paw with or without it). Also say what the data boundary is: which calls go across it on a key, on a frame, and on a save. Owner, 2026-11-22: do not start. This milestone is planned and refined only.

From TASK-77.6 (archived 2026-11-23): the derived-data design (backlog/docs/designs/derived.md, row D6) planned the measure memo, the layout cache and the score of parts of notation on paw.derived, with an edit of one measure that makes one measure again, and a notation frame after a note edit of 1.5 times a frame after a move or less. Keep these goals in the Rust design. paw.derived stays internal until an extension needs it (owner question Q2).
<!-- SECTION:NOTES:END -->
