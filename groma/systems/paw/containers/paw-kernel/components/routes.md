---
type: C4 Component
title: Routes
status: stable
groma:
  id: routes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/routes.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set | teal |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_set | teal |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track | teal |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callback: paw.fx.target | teal |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.add, paw.groups.make, paw.groups.of | teal |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.set | teal |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.device, paw.objects.midi, paw.objects.track | teal |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
