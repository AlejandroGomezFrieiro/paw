---
id: TASK-362
title: 'README and GIFs: bring every scene and alt text up to today''s screens'
status: Done
assignee: []
created_date: '2026-11-24T12:56:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - docs
  - ux
  - agent:worker
milestone: m-9
dependencies: []
priority: high
ordinal: 431000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The tui GIFs date from 2026-11-21 (tour 11-23); since then: track -> part, paw.heads row heads, one motion layer (TM2), devices graph view, Esc in recording, closed-block wanted time. Step 1 (agent, no display): for each docs/images/make/tui-*.sh and cast-basics.sh, run its SETUP and keys headless (tests/tools/run.sh --headless -l, paw.keymap.feed, paw.api.ui_frame_snapshot), check each caption still names the real result, fix the scene where a key or command changed (paw-gifs skill rules: 4G, 5|, / by name, loop rule, CHANGES count). Check README.md text and every alt text of the GIFs against today's behavior. Step 2 (owner, outside the sandbox): make.sh records. Step 3 (orchestrator): read frames, loop, size, commit GIFs with their scenes. gui-*.sh are paused: skip.
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
