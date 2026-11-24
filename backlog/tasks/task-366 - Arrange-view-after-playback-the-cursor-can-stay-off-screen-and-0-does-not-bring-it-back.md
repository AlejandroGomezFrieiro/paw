---
id: TASK-366
title: >-
  Arrange view: after playback the cursor can stay off screen, and 0 does not
  bring it back
status: To Do
assignee: []
created_date: '2026-11-24T13:45:00Z'
updated_date: '2026-11-24T14:30:00Z'
labels:
  - bug
  - ux
  - agent:worker
milestone: m-15
dependencies: []
priority: medium
ordinal: 435000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found 2026-11-24 while making tui-mixer.gif. Cursor at bar 1, Space Space plays, the view follows the playhead to bar 5; stop, gs, then 0: the view stays at bars 5-12 and the cursor (bar 1) is off screen. Cause: follow() in runtime/lua/paw/views/arrange.tl:1544 scrolls for the cursor only when its beat changes (beat ~= self.seen_beat); 0 at bar 1 does not change it. Vim keeps the cursor on screen. Fix: when playback stops (or any motion key ends with the cursor out of view), scroll to the cursor; decide whether a stop brings the view back to the cursor or the cursor to the view (Vim's rule: the cursor moves into the view on a scroll). Test with real keys (lua-testing skill). Then remove the workaround 'l 0' at the end of docs/images/make/tui-mixer.sh.
<!-- SECTION:DESCRIPTION:END -->

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
Orchestrator 2026-11-24: merged in d6f4b482; review MERGE (soft: options wording fixed in c0f4600f); checks in the merge tree: clippy -D warnings clean, rustlint clean, nextest 727 passed, apidoc, hygiene, tl check, lints, mcpscore 163, render gate 7 bit-identical; Lua part arrange passed; mixdiag fails as on main (TASK-371).
<!-- SECTION:NOTES:END -->
