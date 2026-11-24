---
type: C4 Component
title: Commands
status: stable
groma:
  id: commands
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/commands.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api.command_uses, require("paw.api") | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_adjust, paw.api.undo_adjust_cancel, paw.api.undo_current, paw.api.undo_label, paw.api.undo_pending | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, require("paw.events") | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | Invokes supplied callbacks: paw.ex.complete_pattern, paw.ex.complete_range, paw.ex.exec, paw.ex.range | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callbacks: paw.ext.bundled, paw.ext.loaded | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/formats.tl](../../../../../../runtime/lua/paw/formats.tl) | Invokes supplied callbacks: paw.formats.extensions, paw.formats.list | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.device_types | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.human, paw.keymap.parse, paw.keymap.repeat_as | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callback: paw.limit.named | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.list, paw.options.opt, paw.options.show, require("paw.options") | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick.sources | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.merge, require("paw.util") | teal |
| [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | Invokes supplied callbacks: paw.views.files, paw.views.files.here | teal |
