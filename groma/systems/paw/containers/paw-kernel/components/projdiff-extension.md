---
type: C4 Component
title: Project diff extension
status: stable
groma:
  id: projdiff-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/projdiff/git.lua
      symbol: fail
    - scanner: teal
      file: extensions/projdiff/init.lua
    - scanner: teal
      file: extensions/projdiff/lua/projdiff/data.lua
    - scanner: teal
      file: extensions/projdiff/lua/projdiff/diff.lua
    - scanner: teal
      file: extensions/projdiff/lua/projdiff/init.lua
    - scanner: teal
      file: extensions/projdiff/lua/projdiff/merge.lua
    - scanner: teal
      file: extensions/projdiff/lua/projdiff/mergeview.lua
    - scanner: teal
      file: extensions/projdiff/lua/projdiff/text.lua
    - scanner: teal
      file: extensions/projdiff/lua/projdiff/view.lua
    - scanner: teal
      file: extensions/projdiff/manifest.lua
      symbol: projdiff
  group: Bundled extensions
  technology: Lua
description: Shows what changed between two versions of a project and merges projects.
---

Compares what the project holds (tracks, devices, clips, notes, automation, tempo map, markers), not lines of text. git.lua is a git merge driver that does three-way merges of projects.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/projdiff/git.lua](../../../../../../extensions/projdiff/git.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.quit | teal |
| [extensions/projdiff/git.lua](../../../../../../extensions/projdiff/git.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.project_file_text | teal |
| [extensions/projdiff/init.lua](../../../../../../extensions/projdiff/init.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/projdiff/init.lua](../../../../../../extensions/projdiff/init.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/projdiff/init.lua](../../../../../../extensions/projdiff/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/projdiff/init.lua](../../../../../../extensions/projdiff/init.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.group | teal |
| [extensions/projdiff/init.lua](../../../../../../extensions/projdiff/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.notify, paw.ui.page | teal |
| [extensions/projdiff/lua/projdiff/init.lua](../../../../../../extensions/projdiff/lua/projdiff/init.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_decode | teal |
| [extensions/projdiff/lua/projdiff/init.lua](../../../../../../extensions/projdiff/lua/projdiff/init.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/projdiff/lua/projdiff/init.lua](../../../../../../extensions/projdiff/lua/projdiff/init.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.checkpoint_dir, paw.api.checkpoint_list, paw.api.checkpoint_write, paw.api.undo_checkpoint, paw.api.undo_project | teal |
| [extensions/projdiff/lua/projdiff/init.lua](../../../../../../extensions/projdiff/lua/projdiff/init.lua) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callback: paw.qf.set | teal |
| [extensions/projdiff/lua/projdiff/merge.lua](../../../../../../extensions/projdiff/lua/projdiff/merge.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [extensions/projdiff/lua/projdiff/mergeview.lua](../../../../../../extensions/projdiff/lua/projdiff/mergeview.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_load | teal |
| [extensions/projdiff/lua/projdiff/mergeview.lua](../../../../../../extensions/projdiff/lua/projdiff/mergeview.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/projdiff/lua/projdiff/mergeview.lua](../../../../../../extensions/projdiff/lua/projdiff/mergeview.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.project_file_text | teal |
| [extensions/projdiff/lua/projdiff/mergeview.lua](../../../../../../extensions/projdiff/lua/projdiff/mergeview.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.notify, paw.ui.open, paw.ui.view | teal |
| [extensions/projdiff/lua/projdiff/mergeview.lua](../../../../../../extensions/projdiff/lua/projdiff/mergeview.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [extensions/projdiff/lua/projdiff/view.lua](../../../../../../extensions/projdiff/lua/projdiff/view.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/projdiff/lua/projdiff/view.lua](../../../../../../extensions/projdiff/lua/projdiff/view.lua) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callback: paw.qf.go | teal |
| [extensions/projdiff/lua/projdiff/view.lua](../../../../../../extensions/projdiff/lua/projdiff/view.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.notify, paw.ui.open, paw.ui.view | teal |
| [extensions/projdiff/lua/projdiff/view.lua](../../../../../../extensions/projdiff/lua/projdiff/view.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [extensions/projdiff/manifest.lua](../../../../../../extensions/projdiff/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
