---
id: TASK-202
title: TASK-157's api walk leaves plugin and engine state that breaks later tests
status: Done
assignee: []
created_date: '2026-11-23T03:30:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels: []
milestone: m-12
dependencies: []
priority: high
ordinal: 214000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The walk in tests/api_boundary.lua gives each paw.api function wrong arguments. It leaves state behind. Later, tests/core.lua 'vst3 instruments follow the pitch wheel' fails: device_types lists vst3:Surge XT (5), but device_add cannot load it. tests/scope.lua 'scope_rest=frozen plays the rest from files rendered in the background' fails: 3 files, want 2. Alone, each test passes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Find the paw.api calls of the walk that leave each state
- [ ] #2 A kind that device_types lists can be added, or device_types does not list it (product fix with a test)
- [ ] #3 The walk puts back its state (SHAPES restore)
- [ ] #4 The suite's leak check sees this kind of state, if cheap
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-af2e406655c4b064d, commit 4fa81f31 (base e4bcd1e3).
Causes: (1) plugins_rescan registered the plugins on top of the old kinds: each rescan added vst3:<name> (N), which the helper cannot load (core vst3 pitch-wheel test). (2) engine_hold kept a held file after T.fresh (new project), and hold(id, nil) refused a gone track, so scope.tl could not release it (scope_rest=frozen test: 3 held, want 2).
Fixes: paw-plugins rescan unregisters plugin kinds first (Registry::unregister_where); add_dir names new plugins against the registered ones as a helper does; put_project clears held_files; hold(id, nil) works for a gone track. Walk SHAPES restore engine_hold and the given plugins_add_dir folder. suite.lua leak check: new kinds held (per test) and plugins (per part, device_types is ~4 ms with 600 plugins). attr/nest/plugin_state now remove their stub folder. Tutor pianoroll step 2 needs piano roll focus (stale view pitch passed it: the 'only ext' failure).
Not found: 'guide: use articulations with a plugin instrument' (one failure in main's plugins run) passes after the old walk too; cause unknown.
Rust tests to run after build: cargo nextest run -p paw-plugins -E 'test(a_rescan_gives) | test(a_plugin_in_an_added_folder)'; Lua: suite.sh plugins with the walk + victims, the new scope test.

Follow-up commit af4fc815 (on merge tree c50db46f): find_bundles sorted all folders' bundles together, so a helper could give an added folder's plugin a usual plugin's kind. Now bundles come per folder in folder order (first folder wins); the kernel's add_dir naming was right. Fixes a_plugin_in_an_added_folder_gets_the_kind_that_a_helper_gives_it.

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
