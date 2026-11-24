---
id: TASK-189
title: paw_proto::dirs falls back to HOME when an XDG variable is not set
status: Done
assignee: []
created_date: '2026-11-23T00:54:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels: []
milestone: m-12
dependencies: []
priority: low
ordinal: 201000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Left from TASK-167 (2026-11-23): paw-core no longer reads HOME, but paw_proto::dirs falls back to $HOME/.local/... for the data, state and cache folders when XDG_* is not set (used by audio.rs, peaks.rs, panic.rs, fs_api.rs, bake/store.rs, api/system.rs, session.rs). Sealed tests set XDG_*, so tests are not affected. Resolve the folders once at program start (paw-tui main.rs, next to home_dir()) and pass them in, as TASK-167 did for the home folder.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No library code of paw-core or paw-proto reads HOME or XDG_* itself
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
paw_proto::dirs::Dirs holds the resolved base folders; Dirs::from_vars takes the variables from the caller. paw-tui main.rs (dirs(), OnceLock next to home_dir()) and paw-mcp kernel.rs resolve them once; KernelOpts::dirs -> Session::dirs. rpc::default_path/token_path, tls::default_dir, audio::file, peaks::media_dir, bake::Store::user, LocalIndex::default_file, Wire::tls take &Dirs; Connection::tcp and Wire: Default removed. Kept for paused paw-gui: dirs::runtime(), tls::known_path() (the only env readers left in paw-proto). Branch worktree-agent-a3dce68cdd9b3d4a1 (includes TASK-167 branch), commit 4ca5e19a.
<!-- SECTION:NOTES:END -->
