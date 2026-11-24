---
id: TASK-218
title: >-
  Core and extensions: no meta.notation in core, and no paw.<name> entries in
  package.loaded
status: Done
assignee: []
created_date: '2026-11-23T06:42:00Z'
updated_date: '2026-11-24T03:24:00Z'
labels:
  - architecture
  - core
  - notation
milestone: m-10
dependencies: []
priority: medium
ordinal: 246000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-209: paw/query.tl:120-127 and :563, grep.tl:211 and pick/project.tl:281 read meta.notation.art, the notation extension's data. Core changes for an extension must be generic: make the articulation source a registry entry that notation (or articulations) puts. Small text mentions (help.tl:443 tutor-course, views/arrange.tl:1262 :tutor, roll_draw.tl:1321) are fine.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 query.tl, grep.tl and pick/project.tl read no meta.notation path (git grep)
- [x] #2 A registry entry gives the articulations of a note; notation (or articulations) puts it, and an unload takes it away
- [x] #3 Tests: the query of an articulation and the grep of an articulation give the same result as before with notation loaded, and nothing with it unloaded
- [x] #4 Docs are true; Vale reports 0 alerts
- [ ] #5 (TASK-219) No bundled extension sets a package.loaded entry under paw. (git grep)
- [ ] #6 (TASK-219) Each of ara, articulations, mixdiag, sampler, utau and plugstate is required by its own name; their callers, tests and READMEs use the new name
- [ ] #7 (TASK-219) The Lua suite passes; Vale reports 0 alerts on the changed READMEs
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
Criteria 1-4 done on branch worktree-agent-a81a022a6819e41e4 (eff0f276). query.tl, grep.tl and pick/project.tl read no meta.notation. paw.query.marks (registry note_marks) gives {art, text} of a note. Notation puts the score's marks and articulations puts those of the articulation, and an unload takes them away. derived.source_changed('note_marks') makes grep read again. Test in tests/search.lua: query and vimgrep find the staccato with notation and nothing without it. Criteria 5-7 (TASK-219) are not done.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): AC 1 to 4 land with TASK-3 + TASK-217 in batch 19. Plan 6.1 adds: midifile.tl names no device kind of an extension (drum_channel) and reads no meta.lyric. These two points went into bundle A2 (AC 6), where Note.lyric becomes a model field.

PO 2026-11-23 (after batch 18+19, c04f8ae9): AC 1 to 4 are on main (eff0f276): paw.query.marks gives the marks, and query.tl, grep.tl and pick/project.tl read no meta.notation. Left: AC 5 to 7 (TASK-219): ara, articulations, mixdiag and plugstate still set package.loaded['paw.<name>'] (git grep on c04f8ae9). Size S. Do it in phase 1 (wave 1), beside A1, and merge it before W1 (TASK-304), because W1 changes the same READMEs.

AC 5-7 done on branch worktree-agent-a6aa99fe6575cc1d4, commit b5c3c8ae: package.loaded['paw.*'] gone from ara, articulations, mixdiag, plugstate, sampler, utau (only tests/modal.lua keeps paw.views.status); each extension required by its own name; README fixes; a rule in the paw-extension skill. Joins the next batch.

PO 2026-11-24: built, waits to merge (batch 21 or 22); status In Progress until it is on main.

On local main in batches 21+22 (4300ace4, 2026-11-24, not pushed). Full suite passed after two fixes (cab47711 a plugin is not work in flight; 4300ace4 the pick test waits for the walk); nix flake check passed.
<!-- SECTION:NOTES:END -->
