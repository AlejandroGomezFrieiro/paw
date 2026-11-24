---
id: TASK-304
title: >-
  The word part: Track becomes Part in the model, the API, the commands, the
  files and the docs (W1)
status: Done
assignee: []
created_date: '2026-11-23T16:01:00Z'
updated_date: '2026-11-24T05:59:00Z'
labels:
  - architecture
  - rename
  - bundle
milestone: m-10
dependencies:
  - TASK-301
  - TASK-292
  - TASK-95.1
  - TASK-303
  - TASK-218
  - TASK-327
  - TASK-333
  - TASK-294
references:
  - architecture/decisions/0030-the-user-word-part.md
  - architecture/decisions/0018-parts-and-typed-lanes.md
  - architecture/decisions/0032-project-folder-of-parts-and-lanes.md
  - backlog/docs/designs/architecture-plan.md
priority: high
ordinal: 367000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle W1 of the architecture plan, version 2 (backlog/docs/designs/architecture-plan.md V2.7 step 1 and V2.15). The owner chose the user word "part" for the container (ADR 0030).

The rename is wide but has no logic: about 4881 hits in 158 Rust files, 329 Lua and Teal files, 205 Markdown files and 163 test files. Every later bundle then writes the final words one time.

Rules of the batch: W1 runs in a quiet batch. Beside it run only bundles that touch no Lua, no docs and no model/ (G2 in the engine, EL2 in the kernel loop). Each other branch in flight merges before W1, and W1 rebases onto it last. MASTER_ID and master/ stay until MX. The GIFs and the course are W1g.

Read first: the skill .claude/skills/architecture (after batch 19 it is on main), architecture/08-concepts.md and 13-roadmap.md, the ADRs in the references, and backlog/docs/designs/architecture-plan.md (the sections that this ticket names). An Opus agent does the whole bundle in one branch, with its tests and docs in the same commits.

Size: L. Commit by layer, each commit green: Rust (the compiler finds each use), the files, paw.api and Teal (tlcheck), the runtime and the extensions (the suite), the commands and keys, the docs and the tutor.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust: Track is Part, TrackId is PartId, Project.tracks is Project.parts, OwnerRef::Track is OwnerRef::Part; MASTER_ID stays until MX. cargo clippy passes
- [ ] #2 Files: tracks/<name>/track.json is parts/<name>/part.json; master/ stays until MX. A round trip test of the folder
- [ ] #3 paw.api.track_* is paw.api.part_*, paw.tracks is paw.parts, paw.chain.of takes {part = id}; the Teal types and the API reference are made again; tools/tlcheck.sh passes
- [ ] #4 Ex commands :track.* are :part.*; the keys keep their letters unless a key names the word (docs/reference/key-rule.md lists each change); messages say part
- [ ] #5 Runtime and extensions: no public name, message or doc comment says track for the container (git grep with an allow-list for other senses: the sound track of a video, a MIDI file track, to track a value)
- [ ] #6 Docs, READMEs and the tutor's lessons say part; the guide tests pass; Vale reports 0 alerts
- [ ] #7 Each layer is one commit, and the suite passes at each commit
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
PO 2026-11-24: dependencies added for each branch in flight that W1 rebases onto last (batch 21: TASK-301, TASK-303, TASK-218, TASK-333; batch 22: TASK-95.1, TASK-327, TASK-294). EL1 (TASK-292), D4 (TASK-302) and TASK-325 are on main.

Done on branch worktree-agent-a556bd5634c937ae2 (base 4f9ee042 + G2 83e4ecb3): 644b79cf (free the word part: portion, Piece, Member, sub, vpart, component), a39bfea1 (merge G2), eb72366c (kernel, API, runtime), dee0a6e0 (extensions), cb958531 (docs, skills), 6000ca5b (partlint + allow-list 42 files), cf291dd3 (tests, goldens). Files parts/<name>/part.json; paw.api.part_*, :part.*; <leader>t stays the parts group. Needs on the orchestrator's build: full suite, suite.sh plugins, PAW_BLESS on 21 golden screens (padding only; review diffs), apidoc check, nix flake check (partlint). The agent ran cargo test --workspace once by mistake (it built a debug paw and started lua_suite; stopped). paw-gui does not build until it gets the rename. Owner questions: notation :part.* → :score.part.* or :staff.*?; <Space>t stays parts?

Batch 22 head 3ceda2c1 merged into W1: new head 547888c9 (10 conflicts, all on the batch side with the word renamed; engine keeps Piece and map.pieces). Clippy 0, paw-core/paw-engine tests pass, lints and partlint pass. After build also run --shuffle and extensions_api, frontend, project_folder, record_mix, shada, windows, ui.

On local main (f4d81913, 2026-11-24, not pushed). Full suite: 1 failure, the wall-time double-click test (tuimouse.lua:284) that TASK-330 flagged under load and TASK-149 fixes; nix flake check passed (with partlint). Fixes at merge: the album tag keeps the word track (render.tl tag_names, docs, tests/tags.lua, allow-list); 16 golden screens re-blessed (padding and the new word only).
<!-- SECTION:NOTES:END -->
