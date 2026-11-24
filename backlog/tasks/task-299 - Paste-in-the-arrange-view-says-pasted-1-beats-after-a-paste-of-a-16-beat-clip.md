---
id: TASK-299
title: >-
  Paste in the arrange view says 'pasted 1 beats' after a paste of a 16-beat
  clip
status: Done
assignee: []
created_date: '2026-11-23T14:00:00Z'
updated_date: '2026-11-23T23:03:00Z'
labels: []
milestone: m-15
dependencies: []
priority: medium
ordinal: 361000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the agent of TASK-93 in the pod build: a paste in the arrange view says 'pasted 1 beats' when it pasted a clip of 16 beats. The count and the plural are wrong.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The message names what was pasted with the right length and plural (a test with real keys: yank a 16-beat clip, paste, check the message)
<!-- AC:END -->

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
Branch worktree-agent-a171af34fc940b21e, commit 0a1e1f1b. Cause: the cast's keys (4Gw from beat 16) put the cursor at beat 32, past the melody, so vic found no clip and y yanked one empty beat. paw gave the length right, with the wrong plural. Fix: paw.util.amount(n, word) gives the plural only when n is not 1; used in the yank and paste messages of the arrange view, the snap messages, the region message and the roll's tie message. Test: tests/robust.lua 'a yank and a paste say how many beats they took, in the singular for one' (real keys).

On main in batch 20 (5041115e, pushed 2026-11-24 with the tag pre-parts). Full suite passed after one test fix (5041115e: three tests and the time-axis test expected the null backend); nix flake check passed.

PO 2026-11-24: AC checked against main: paw.util.amount in util.tl; real-keys test in tests/robust.lua.
<!-- SECTION:NOTES:END -->
