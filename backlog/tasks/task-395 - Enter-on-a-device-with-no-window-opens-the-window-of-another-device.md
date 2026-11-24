---
id: TASK-395
title: Enter on a device with no window opens the window of another device
status: Done
assignee: []
created_date: '2026-11-24T20:34:00Z'
updated_date: '2026-11-24T20:49:00Z'
labels:
  - bug
  - devices
  - agent:worker
dependencies: []
priority: medium
ordinal: 464000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In the device panel, Enter (device.editor) on a device that has no window of its own (a built-in effect, a Lua device) opens the window of the first device of the part that has one. Expected: open nothing, and say that the device has no window and where its parameters are.

Cause: runtime/lua/paw/defaults/devices.lua, command device.editor: when the selected device has no editor, it falls back to the part's first device with an editor. The fallback is for the case with no selected device only (the arrange view, the mixer with no device row).

A draft of the fix and of a real-key test is in the orchestrator's scratchpad (device-enter.diff). The draft test does not run: the sealed suite finds no test plugin with a window, so it skips. The test must fail on the old code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Enter on a device with no window opens no window and gives a message that names the device
- [ ] #2 With no device selected, device.editor still opens the part's first window
- [ ] #3 A real-key test fails on the old code and passes on the new
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
On main in merge 3644a852 (2026-11-24), set Done by tools/board-sync.sh.
<!-- SECTION:NOTES:END -->
