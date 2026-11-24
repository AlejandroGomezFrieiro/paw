---
id: TASK-167
title: >-
  Session: the home folder as a value (folder.rs outside_name and resolve read
  HOME)
status: Done
assignee: []
created_date: '2026-11-22T22:28:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels: []
milestone: m-12
dependencies: []
priority: medium
ordinal: 179000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-162 (2026-11-23). paw-core session/folder.rs outside_name and resolve read HOME to shorten and expand ~ in project file paths; paw-tui main.rs expands ~ too. Put home in KernelOpts and the Session, resolved once at the program start, and pass it in. Starts after the session branches of TASK-7.11, 85.1 and 77.7 are on main.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No library code of paw-core reads HOME
- [ ] #2 A Rust test gives its own home folder and checks the ~ form of a path
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a3f99512f442fefcf, commit 07aaa098 (on main bc16df6d + TASK-162 branch merged). folder::Home (Option<PathBuf>) owns outside_name and resolve; KernelOpts::home (paw-tui home_dir() reads HOME once) -> Session.home -> layout/layout_cached/read/read_from/read_with/read_chain/read_outside_track, undo-file Job, media.json. Test folder::tests::a_file_in_the_home_folder_is_named_from_it (in memory, both with and without a home). Left: paw_proto::dirs still falls back to $HOME when XDG_* is unset (data/state/cache, used by paw-core audio.rs, peaks.rs, panic.rs, fs_api.rs, bake/store.rs, api/system.rs, session.rs) - a possible follow-up. paw-gui does not build KernelOpts: not affected.
<!-- SECTION:NOTES:END -->
