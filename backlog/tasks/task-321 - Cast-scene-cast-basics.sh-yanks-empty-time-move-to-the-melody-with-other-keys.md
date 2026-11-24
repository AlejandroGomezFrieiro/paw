---
id: TASK-321
title: 'Cast scene cast-basics.sh yanks empty time: move to the melody with other keys'
status: To Do
assignee: []
created_date: '2026-11-23T16:23:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:worker
milestone: m-9
dependencies: []
priority: low
ordinal: 390000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the agent of TASK-299: the keys of docs/images/make/cast-basics.sh (4Gw from beat 16) put the cursor at beat 32, past the melody, so vic finds no clip and the yank and paste in the recorded session act on one empty beat. Move to the melody with other keys (for example 4G17|) and record the cast again.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The recorded session yanks and pastes the melody clip, and the message names its 16 beats
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
