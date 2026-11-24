---
type: C4 Component
title: Undo tree extension
status: stable
groma:
  id: undotree-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/undotree/init.lua
      symbol: write
    - scanner: teal
      file: extensions/undotree/lua/undotree/init.lua
    - scanner: teal
      file: extensions/undotree/lua/undotree/paint.lua
    - scanner: teal
      file: extensions/undotree/lua/undotree/view.lua
    - scanner: teal
      file: extensions/undotree/manifest.lua
      symbol: undotree
  group: Bundled extensions
  technology: Lua
description: Shows the undo tree, with named checkpoints and A/B listening.
---

A window on the undo tree of the session. The user can name checkpoints and listen to two states, one after the other.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/undotree/init.lua](../../../../../../extensions/undotree/init.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.checkpoint_delete, paw.api.undo_diff, paw.api.undo_name | teal |
| [extensions/undotree/init.lua](../../../../../../extensions/undotree/init.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/undotree/init.lua](../../../../../../extensions/undotree/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/undotree/init.lua](../../../../../../extensions/undotree/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.float, paw.ui.input, paw.ui.notify, paw.ui.page | teal |
| [extensions/undotree/lua/undotree/init.lua](../../../../../../extensions/undotree/lua/undotree/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/undotree/lua/undotree/init.lua](../../../../../../extensions/undotree/lua/undotree/init.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.checkpoint_dir, paw.api.checkpoint_list, paw.api.checkpoint_restore, paw.api.checkpoint_write, paw.api.undo_checkpoint, paw.api.undo_current, paw.api.undo_goto, paw.api.undo_keep, paw.api.undo_name, paw.api.undo_step, paw.api.undo_travel, paw.api.undo_tree | teal |
| [extensions/undotree/lua/undotree/init.lua](../../../../../../extensions/undotree/lua/undotree/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/undotree/lua/undotree/init.lua](../../../../../../extensions/undotree/lua/undotree/init.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/undotree/lua/undotree/init.lua](../../../../../../extensions/undotree/lua/undotree/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.page | teal |
| [extensions/undotree/lua/undotree/paint.lua](../../../../../../extensions/undotree/lua/undotree/paint.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_view_snapshot | teal |
| [extensions/undotree/lua/undotree/paint.lua](../../../../../../extensions/undotree/lua/undotree/paint.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_current, paw.api.undo_diff | teal |
| [extensions/undotree/lua/undotree/paint.lua](../../../../../../extensions/undotree/lua/undotree/paint.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.cell, paw.canvas.close, paw.canvas.palette, require("paw.canvas") | teal |
| [extensions/undotree/lua/undotree/paint.lua](../../../../../../extensions/undotree/lua/undotree/paint.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.fields | teal |
| [extensions/undotree/lua/undotree/paint.lua](../../../../../../extensions/undotree/lua/undotree/paint.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.view | teal |
| [extensions/undotree/lua/undotree/paint.lua](../../../../../../extensions/undotree/lua/undotree/paint.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/undotree/lua/undotree/view.lua](../../../../../../extensions/undotree/lua/undotree/view.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/undotree/lua/undotree/view.lua](../../../../../../extensions/undotree/lua/undotree/view.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/undotree/lua/undotree/view.lua](../../../../../../extensions/undotree/lua/undotree/view.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.redo, paw.api.undo, paw.api.undo_current, paw.api.undo_diff, paw.api.undo_name | teal |
| [extensions/undotree/lua/undotree/view.lua](../../../../../../extensions/undotree/lua/undotree/view.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [extensions/undotree/lua/undotree/view.lua](../../../../../../extensions/undotree/lua/undotree/view.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.transport | teal |
| [extensions/undotree/lua/undotree/view.lua](../../../../../../extensions/undotree/lua/undotree/view.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.float, paw.ui.input, paw.ui.notify, paw.ui.open, paw.ui.view | teal |
| [extensions/undotree/lua/undotree/view.lua](../../../../../../extensions/undotree/lua/undotree/view.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [extensions/undotree/manifest.lua](../../../../../../extensions/undotree/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
