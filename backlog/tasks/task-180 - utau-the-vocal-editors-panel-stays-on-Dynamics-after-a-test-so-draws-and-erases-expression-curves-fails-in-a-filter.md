---
id: TASK-180
title: >-
  utau: the vocal editor's panel stays on Dynamics after a test, so 'draws and
  erases expression curves' fails in a filter
status: Done
assignee: []
created_date: '2026-11-23T00:04:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels: []
milestone: m-12
dependencies: []
priority: medium
ordinal: 192000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seen by TASK-178 (2026-11-23): suite.sh only curve fails 'the vocal editor draws and erases expression curves under the notes' (extensions/utau/tests_singing.lua:498, got dyn, want pitd); it passes alone and fails the same on main. An earlier test in that filter leaves the vocal editor's panel on Dynamics. Find the test that leaves it, put it back with T.after, or add the panel to the leak check if it is kernel or view state that crosses files (TASK-144's kinds).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 suite.sh only curve passes
- [ ] #2 The test that leaves the panel puts it back, or the leak check names it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cause: two tests in extensions/utau/tests.lua (the pictures-strips test and '= puts the curve back') set editor.curve = dyn and left it; each alone makes suite.sh only curve fail. The utau editor is a module singleton and the state stays inside the utau tests, so no new leak-check kind. Fix: keep_curve() helper (T.after) in tests.lua, also before :utau.curve ene/spk1 in the AI pitch test; the failing test also restores what it changes. Its assertions are unchanged. Branch worktree-agent-ad2c115ddbc0bf08f (TASK-144 merged in), commit c357ea85. suite.sh only curve, utau, vocal editor, the curve: all passed. fmtcheck and luacheck clean.
<!-- SECTION:NOTES:END -->
