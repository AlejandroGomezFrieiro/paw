---
type: C4 Component
title: Templates extension
status: stable
groma:
  id: templates-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/templates/init.lua
    - scanner: teal
      file: extensions/templates/lua/templates/commands.lua
    - scanner: teal
      file: extensions/templates/lua/templates/init.lua
    - scanner: teal
      file: extensions/templates/manifest.lua
      symbol: templates
  group: Bundled extensions
  technology: Lua
description: Saves tracks and device chains as templates to make again.
---

A track, a group of tracks or a chain of devices is saved under a name, and the user makes it again in any project.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/templates/init.lua](../../../../../../extensions/templates/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/templates/lua/templates/commands.lua](../../../../../../extensions/templates/lua/templates/commands.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track | teal |
| [extensions/templates/lua/templates/commands.lua](../../../../../../extensions/templates/lua/templates/commands.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.menus | teal |
| [extensions/templates/lua/templates/commands.lua](../../../../../../extensions/templates/lua/templates/commands.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.is_group | teal |
| [extensions/templates/lua/templates/commands.lua](../../../../../../extensions/templates/lua/templates/commands.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.group, paw.keymap.set | teal |
| [extensions/templates/lua/templates/commands.lua](../../../../../../extensions/templates/lua/templates/commands.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/templates/lua/templates/commands.lua](../../../../../../extensions/templates/lua/templates/commands.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.notify | teal |
| [extensions/templates/lua/templates/init.lua](../../../../../../extensions/templates/lua/templates/init.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api.decode, paw.api.encode | teal |
| [extensions/templates/lua/templates/init.lua](../../../../../../extensions/templates/lua/templates/init.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [extensions/templates/lua/templates/init.lua](../../../../../../extensions/templates/lua/templates/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_set | teal |
| [extensions/templates/lua/templates/init.lua](../../../../../../extensions/templates/lua/templates/init.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/templates/lua/templates/init.lua](../../../../../../extensions/templates/lua/templates/init.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.index, paw.cursor.set_track, paw.cursor.track | teal |
| [extensions/templates/lua/templates/init.lua](../../../../../../extensions/templates/lua/templates/init.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.add, paw.groups.is_group, paw.groups.members | teal |
| [extensions/templates/lua/templates/init.lua](../../../../../../extensions/templates/lua/templates/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.restore_device, paw.objects.restore_track, paw.objects.track | teal |
| [extensions/templates/manifest.lua](../../../../../../extensions/templates/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
