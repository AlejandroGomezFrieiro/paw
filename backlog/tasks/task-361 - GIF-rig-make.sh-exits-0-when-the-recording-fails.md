---
id: TASK-361
title: 'GIF rig: make.sh exits 0 when the recording fails'
status: Done
assignee: []
created_date: '2026-11-24T12:56:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - bug
  - docs
  - agent:worker
milestone: m-9
dependencies: []
priority: medium
ordinal: 430000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-11-24: inside the Claude Code sandbox, docs/images/make/make.sh tui-help printed 'Cannot open display :177' from ffmpeg and 'Failed creating new xdo instance' for each key, made no GIF, and exited 0. A failed scene must exit non-zero with the reason (no display, no recording, no GIF written), so a run that made nothing never looks like a success. Check rig.sh (set -e or explicit checks after Xvfb start, ffmpeg start, xdotool) and gif.py.
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
Absorbed by TASK-363 step 2.
<!-- SECTION:NOTES:END -->
