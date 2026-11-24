---
id: TASK-80.1
title: 'Plugins: tell CLAP and VST3 plugins that a render is offline'
status: Done
assignee: []
created_date: '2026-11-23T06:14:00Z'
updated_date: '2026-11-23T07:01:00Z'
labels:
  - plugins
  - render
milestone: m-3
dependencies: []
parent_task_id: TASK-80
priority: medium
ordinal: 231000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Split from TASK-80 on 2026-11-23 (the fix that belongs there). Today paw renders, exports, freezes and bakes without telling a plugin that the render is offline, so a plugin with its own quality setting uses its realtime quality.

What to build:
- CLAP: the clap.render extension. set(CLAP_RENDER_OFFLINE) before an offline render, and back to realtime after it. A plugin without the extension is not changed.
- VST3: setupProcessing with processMode = kOffline for a render, and kRealtime again after it.
- LV2 has no such call: docs/reference/render.md says so.
- The sandbox (the plugin host process) passes the mode on.

Read first: crates/paw-plugins (the CLAP host: how extensions are queried; the VST3 host: setupProcessing; the sandbox protocol), crates/paw-core/src/session/render.rs, session/offline.rs, freeze.rs, crates/paw-core/src/bake (bakes). .claude/skills/rust-skills (the audio thread rules) and rust-testing (the stub plugin).

Do not touch: the option paw.opt.quality (TASK-80).

Size: S to M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Rust test with the stub CLAP plugin: an offline render calls clap.render set(OFFLINE) before the first block and set(REALTIME) after it
- [x] #2 Rust test: VST3 setupProcessing gets kOffline for a render and kRealtime after it
- [x] #3 The no_alloc tests of paw-engine and paw-plugins pass
- [x] #4 render.md says what paw tells each plugin format; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a4955caed125aa914, commit e764028c (on main e46ecc13). Main already did the behavior: sync/devices.rs calls Controller::set_offline(true) on each device made for a render (render, export, stems, freeze, measure), before its first block; CLAP clap.render set(OFFLINE), VST3 setupProcessing kOffline, LV2 free-wheeling port, sandbox Request::SetOffline. Render instances are private and dropped after the render, so no set(REALTIME) after: the live instances are never set offline. Added: stub CLAP clap.render + stub.render; paw-plugins test a_plugin_set_offline_renders_offline_until_it_is_set_back; vst3 set_up_again + spy unit test a_render_sets_the_processor_up_offline_and_then_realtime_again; paw-core sync test a_plugin_made_for_a_render_is_set_offline_before_its_first_block; render.md section 'Plugins in a render'. render.rs not changed.

PO 2026-11-23, for the check at merge: AC #1 and #2 say set(REALTIME) after the render. The agent found that a render uses its own instances, dropped after the render, so main never sets a live instance offline. The tests check that an instance set offline renders offline until it is set back (stub CLAP), and setupProcessing kOffline then kRealtime (VST3 spy). Accept this as meeting #1 and #2 if the code agrees.

PO 2026-11-23 check of main: the tests are on main (paw-plugins tests/stub.rs a_plugin_set_offline_renders_offline_until_it_is_set_back, vst3 controller.rs a_render_sets_the_processor_up_offline_and_then_realtime_again, paw-core sync a_plugin_made_for_a_render_is_set_offline_before_its_first_block). render.md 'Plugins in a render' says what each format gets; Vale 0. A render uses its own instances, so the set back to realtime is checked on the instance, as accepted in the earlier note. no_alloc: the orchestrator's build at merge. All criteria met.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged in 1598fefc. Each plugin instance made for a render is set offline before its first block (CLAP clap.render, VST3 kOffline, LV2 free-wheeling, sandbox SetOffline). Tests and render.md added. The option paw.opt.quality stays in TASK-80.
<!-- SECTION:FINAL_SUMMARY:END -->
