---
id: TASK-162
title: 'paw-plugins: the plugin folders are an argument, not read inside the library'
status: Done
assignee: []
created_date: '2026-11-22T20:38:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels: []
milestone: m-12
dependencies: []
priority: medium
ordinal: 174000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the jorgeortiz.dev review (2026-11-22). usual_dirs in crates/paw-plugins/src/lib.rs (near line 544) reads HOME, USER and the *_PATH variables inside the library; presets.rs (near 380), libs.rs (near 57) and window.rs (near 94, 112) also read HOME, and ADDED_DIRS is a global. main resolves one PluginDirs value at start and passes it in, so a unit test gives folders under a TempDir and never reaches the machine. Part of the self-contained rule (TASK-161).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No function of paw-plugins outside main's start reads HOME, USER or a *_PATH variable
- [ ] #2 ADDED_DIRS is a field of a value that the caller owns, not a global
- [ ] #3 Unit tests of the scan use folders under a TempDir
- [ ] #4 The users' behavior is the same: the same folders are searched in the same order
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a973c996cfd014527 (commit f9f7684a, on top of TASK-100 and TASK-161 merged in). New crates/paw-plugins/src/dirs.rs: PluginDirs (clap, vst3, lv2, libraries, vst3_presets, added). paw-tui plugins.rs resolves it once at the start (from_env; for_helper in plugin-host, which also adopts PAW_PLUGIN_DIRS) and passes it to register, rescan, add_dir, sandbox::wrap, serve and scan_main. ADDED_DIRS is now the added field of the value that paw-tui owns (Rc<RefCell>); each RemoteFactory carries the added folders of the time it was made. libs.rs, presets.rs (vst3_preset_dirs takes the roots), the lilv world (world_in) and the LV2 editors take folders from the value. repair_display_env takes home; plugin-host repairs the display at its start. Registry::plugin_dirs + paw.api.plugins_dirs; plugstate share_dirs and frameworks.binary_of use it. Not done: paw-core session/folder.rs outside_name/resolve still read HOME (project paths, a different concern, paw-core): needs a follow-up ticket. The orchestrator must run apidoc (paw --clean --no-plugins -l tools/apidoc.lua) after the build: api.md and runtime/types need paw.api.plugins_dirs.
<!-- SECTION:NOTES:END -->
