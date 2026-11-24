---
id: TASK-210
title: >-
  projdiff: compare a project that is saved as a folder (file, git revision,
  snapshot)
status: Done
assignee: []
created_date: '2026-11-23T06:35:00Z'
updated_date: '2026-11-23T08:31:00Z'
labels:
  - projdiff
  - extensions
  - project-files
milestone: m-2
dependencies:
  - TASK-7.15
priority: high
type: bug
ordinal: 238000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-7.15 (its agent found it). A project is a folder (docs/reference/project-files.md). extensions/projdiff still reads a version of a project as one JSON file: M.decode, M.file and M.git in extensions/projdiff/lua/projdiff/init.lua decode one file with paw.api.json_decode. Thus `:Pdiff HEAD~2`, `:Pdiff other` and a snapshot kept as a file do not work on a project saved as a folder. The undo states (`:Pdiff #7`) and `:Pdiff` without an argument read the project in memory.

What to build:
- projdiff reads a version of a project folder: a folder on disk, and the same folder at a git revision (git show or git archive of the folder, into a scratch folder, or a read from memory).
- Use the reader of the kernel for a project folder if one exists (TASK-82.1 reads a project folder from memory), not a second reader in Lua.
- The README of projdiff and `:Pdiff`'s description name folders, not .json files.

Read first: extensions/projdiff (init.lua, lua/projdiff/init.lua, git.lua, tests.lua, README.md); docs/reference/project-files.md; the notes of TASK-82.1 and TASK-7.15.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test (extensions/projdiff/tests.lua): :Pdiff <folder> compares the open project with another project folder and lists the changes
- [x] #2 Test: :Pdiff HEAD~1 on a project folder in a scratch git repository lists the change of the last commit
- [x] #3 Test: a snapshot kept beside a saved project compares with the project now
- [x] #4 The README of projdiff and the command's description say folders; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a5ea639fa4e167d90, commit 64d62a42 (on top of 7f02e829 + merge of worktree-agent-a75e8062e2b7866c6, TASK-7.15). New kernel API paw.api.project_read(path, files?) (session::folder Session::project_read, uses read_from with MemoryFiles when files are given) and paw.api.project_file_managed(rel). projdiff: M.folder, M.git reads a folder at a revision with git ls-tree + one git cat-file --batch (no checkout), M.version detects project folders. 3 new tests in extensions/projdiff/tests.lua (folder, git HEAD~1, snapshot). Lua tests passed with the shared binary and a scratch stand-in for project_read (not committed); after the build: apidoc regenerate, then suite.sh only projdiff, cargo test -p paw-core folder. README, :Pdiff desc, project-files.md, about-project-files.md updated; Vale 0.

Merged to main in batch 14 (23350734); full suite and flake-equivalent checks passed.
<!-- SECTION:NOTES:END -->
