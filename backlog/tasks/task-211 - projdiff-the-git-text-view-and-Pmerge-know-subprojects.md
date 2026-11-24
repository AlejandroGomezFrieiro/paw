---
id: TASK-211
title: >-
  projdiff: :Pmerge on a project folder knows subprojects, Enter on a change
  goes into its subproject; the whole-project textconv and merge driver go
status: Done
assignee: []
created_date: '2026-11-23T06:35:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - projdiff
  - extensions
  - nest
milestone: m-2
dependencies:
  - TASK-210
priority: medium
ordinal: 239000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-7.15. Refined by the PO on 2026-11-23 after the design decision of the orchestrator (see the notes).

Decision: git compares and merges a project folder file by file. The .midi2 textconv (`paw clip cat`, docs/reference/project-files.md) stays. :Pdiff and :Pmerge read the whole folder (TASK-210 gives paw.api.project_read and the reader of a git revision). The textconv and the merge driver for a whole project file (extensions/projdiff/git.lua, the setup in the README, :Pgit) go: a project is a folder now, so they do nothing useful.

What to build:
- Remove git.lua textconv and merge, the README section "How to diff and merge projects with git" and the parts of :Pgit that set them up. Remove text.lua if nothing else uses it.
- :Pmerge on a project folder with a git merge in progress reads the three versions (base, ours, theirs) of the folder from the git index (stages 1, 2 and 3) through paw.api.project_read, merges them with merge.lua, and shows the conflicts.
- The conflicts are grouped as diff.lua groups a diff: a conflict inside a subproject is under the heading subproject <id> "<name>", also two levels deep.
- A choice (co, ct, cb) writes the result back to the open project, inside the subproject when the conflict is there. One choice is one undo step.

Read first: extensions/projdiff (init.lua, merge.lua, mergeview.lua, diff.lua, git.lua, README.md); the TASK-7.15 commit b74230d2 and the TASK-210 commit; docs/reference/limits.md; backlog/docs/designs/nest.md section 4.10.

Depends on: TASK-210 (projdiff reads a project folder).
Do not touch: the .midi2 textconv; the kernel folder reader beyond a generic need.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test: :Pmerge on a project folder with a conflict in a track of the song shows the conflict, and co writes our side back
- [x] #2 Test: a conflict inside a subproject shows under the subproject's name, also two levels deep, and the choice writes it back inside the subproject
- [x] #3 git.lua textconv and merge, their README section and their setup in :Pgit are gone; no test uses them
- [x] #4 The README of projdiff and limits.md are true; Vale reports 0 alerts
- [x] #5 (TASK-212) Test with real keys: <Space>gd, then Enter on a change inside a subproject, puts the window in the subproject's scope with the cursor on the changed track
- [x] #6 (TASK-212) Test: Enter on a change two levels deep goes into the inner subproject
- [x] #7 (TASK-212) Test: Enter on a change of the song does what it did before
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Orchestrator 2026-11-23 (design): git compares a project folder file by file (the .midi2 textconv that exists); :Pdiff and :Pmerge read the whole folder. Drop the whole-project textconv and merge driver. This ticket gets smaller.

PO 2026-11-23: description and criteria rewritten to the decision above (the old criterion for the whole-project textconv went). Size S to M became M.

Merged from TASK-212 (projdiff: Enter on a change inside a subproject goes into that subproject) by the PO on 2026-11-23.

Its description:
Follow-up of TASK-7.15 (its agent named it). The window of :Pdiff and its quickfix list now show a change inside a subproject under the subproject's name. Enter on such a change was not checked: it must go inside that subproject (as a choice of :nest.list does) and put the cursor on the changed track or clip. For a subproject inside a subproject, Enter goes into the inner one.

Read first: extensions/projdiff/lua/projdiff/view.lua and diff.lua; runtime/lua/paw/nest.tl (go inside a subproject); docs/reference/subprojects.md; tests/scope.lua; extensions/projdiff/tests.lua (the TASK-7.15 tests).

Size: S.

Its notes:
PO 2026-11-23: TASK-210 also changes projdiff. Start this one after TASK-210, or keep the change to view.lua and diff.lua.

PO 2026-11-23: dependency on TASK-210 added (both change projdiff; start after it merges).

PO 2026-11-23: Bundle: both change extensions/projdiff (view.lua, diff.lua, merge) on top of TASK-210. Size M to L.

PO 2026-11-23 (after batch 14): TASK-210 is on main (64d62a42, merge e9c61f01). It gives paw.api.project_read(path, files?) and paw.api.project_file_managed(rel). projdiff has M.folder and M.git (git ls-tree and one git cat-file --batch, no checkout) and M.version. Read the three index stages with the same reader. The ticket can start now.

Merged to main in batch 16 (cd367da1); full suite and checks passed after three merge fixes.

Agent's notes (its own write was refused by the worktree guard): branch commit 980d1237; added paw.api.project_replace; :Pdiff.qf entries do not enter a subproject (in limits.md).
<!-- SECTION:NOTES:END -->
