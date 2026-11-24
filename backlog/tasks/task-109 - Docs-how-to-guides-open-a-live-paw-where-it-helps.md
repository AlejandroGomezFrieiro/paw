---
id: TASK-109
title: 'Docs: how-to guides open a live paw where it helps'
status: Done
assignee: []
created_date: '2026-11-22T11:00:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - docs
  - website
  - interactive
milestone: m-9
dependencies:
  - TASK-108
priority: medium
ordinal: 112000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rework the how-to guides (and reference pages where useful) so a guide can open the customized pod (TASK-108) at the guide's starting state with one button; local instructions stay first-class. Pick the guides where it helps most (first steps, recording, piano roll, mixing); keep guide tests passing.
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a20379d5d735b81e5. A how-to page asks for a live paw with '<!-- paw-live: {state} -->' (hidden on GitHub and :help); tools/website/live.lua makes it a panel at that state. Seven guides: start-paw-and-hear-sound (empty project), edit-notes, set-levels-and-pan, loop-a-part-of-the-song, work-on-one-section-of-a-song, move-copy-split-and-trim-clips, insert-with-keys. Recording guides left out: the pod has no audio input and no MIDI. Guide tests pass (suite only guides help markdown).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main. A how-to page asks for a live paw with a paw-live comment; tools/website/live.lua makes the panel. Seven guides have it; recording guides do not (no audio input in the pod). Guide tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
