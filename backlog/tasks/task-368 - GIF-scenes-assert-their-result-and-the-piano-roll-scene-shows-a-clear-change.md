---
id: TASK-368
title: GIF scenes assert their result, and the piano roll scene shows a clear change
status: To Do
assignee: []
created_date: '2026-11-24T14:16:00Z'
labels:
  - docs
  - tooling
  - agent:worker
milestone: m-9
dependencies: []
priority: medium
ordinal: 437000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the report of the GIF rig ticket. The check mode (nix run .#gifs -- --check) fails only when a key errors or paw shows an error message. A scene whose screen is wrong still passes: the stale I chapter of tui-pianoroll passed. Also, the vib chapter of tui-pianoroll selects bar 9, which holds one short note, so the semitone change is hard to see on the GIF. Files: docs/images/make/rig.sh, the tui-*.sh scenes, the paw-gifs skill.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each tui-*.sh scene asserts its result with a Wait plus Screen regex after its last key of each chapter
- [ ] #2 --check fails with the scene, the chapter and the screen text when an assertion does not match
- [ ] #3 The stale I chapter of tui-pianoroll fails --check before its fix and passes after
- [ ] #4 The vib chapter of tui-pianoroll moves the cursor to a bar with several notes, and the GIF shows the semitone change
- [ ] #5 The paw-gifs skill and the page that names the check mode tell how to write an assertion
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
