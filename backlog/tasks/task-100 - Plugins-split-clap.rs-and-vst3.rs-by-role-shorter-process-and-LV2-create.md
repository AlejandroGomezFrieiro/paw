---
id: TASK-100
title: 'Plugins: split clap.rs and vst3.rs by role, shorter process and LV2 create'
status: Done
assignee: []
created_date: '2026-11-22T10:38:00Z'
updated_date: '2026-11-23T02:07:00Z'
labels:
  - rust
  - plugins
  - quality
milestone: m-10
dependencies: []
priority: medium
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: clap.rs and vst3.rs become folders by role, as lv2/ is, and the longest plugin functions split by step. Finding F6 of the architecture review (backlog/docs/designs/architecture-review.md). Prepares TASK-47.

Today: crates/paw-plugins/src/clap.rs (1795 lines) and vst3.rs (1900 lines) each hold the library load, list, factory, host callbacks, run loop, audio device, controller, editor, state streams and event conversion. process is 202 lines (clap.rs:726) and 225 lines (vst3.rs:1195); lv2/factory.rs create 275 lines; lv2/controller.rs open_editor 226 lines.

Change: clap/ and vst3/ with mod.rs (PluginFormat), library.rs, host.rs, factory.rs, device.rs (audio thread only), controller.rs, editor.rs, state.rs, events.rs. Each process in three steps: events in, the call, events and audio out. The long LV2 functions split by step. No change of behavior; each SAFETY comment stays with its block.

Read first: the review, F6; crates/paw-plugins/src/clap.rs, vst3.rs, lv2/; .claude/skills/rust-skills/paw-crates.md (the CLAP host notes); .claude/skills/rust-skills (unsafe-*).
Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No file of paw-plugins has more than about 600 lines of code
- [ ] #2 No process function has more than about 80 lines
- [ ] #3 paw-plugins tests and tests/no_alloc.rs pass; the Lua plugin tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a78f62ca73014d5ac, commits afa4a98b b87e2410 21c3ecb3 089ea5c6, merged main in d7b89c45. clap and vst3 are folders by role. process is 76 lines in CLAP, 79 in VST3, 13 in LV2, each in three named steps. LV2 create is 167 lines, open_editor 66. Largest file lib.rs with 573 lines of code. cargo check and clippy of paw-plugins are clean. The orchestrator runs cargo test of paw-plugins and the Lua plugin tests.
<!-- SECTION:NOTES:END -->
