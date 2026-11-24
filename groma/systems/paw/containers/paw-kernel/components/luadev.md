---
type: C4 Component
title: Luadev
status: stable
groma:
  id: luadev
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/luadev.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | [crates/paw-core/src/luadev_api.rs](../../../../../../crates/paw-core/src/luadev_api.rs) | Invokes supplied callbacks: paw.api.lua_devices, paw.api.lua_devices_add, paw.api.lua_devices_remove, paw.api.lua_devices_rescan | teal |
| [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track | teal |
| [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.on | teal |
| [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.every | teal |
| [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.master, paw.objects.tracks | teal |
| [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
