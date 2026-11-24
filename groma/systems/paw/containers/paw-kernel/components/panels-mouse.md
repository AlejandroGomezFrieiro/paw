---
type: C4 Component
title: Panels mouse
status: stable
groma:
  id: panels-mouse
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/panels_mouse.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_editor, paw.api.device_get, paw.api.device_remove | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.device, paw.address.param | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.move_track, paw.cursor.set_track | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.clear_peak, paw.draw.db_text | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.act, paw.frontend.routing | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/mouse_menus.tl](../../../../../../runtime/lua/paw/mouse_menus.tl) | Invokes supplied callbacks: paw.mouse_menus.lens, paw.mouse_menus.param, paw.mouse_menus.track, require("paw.mouse_menus") | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.grab, paw.mouse.has, paw.mouse.hint, paw.mouse.wheel | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | Invokes supplied callback: paw.params.fraction | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.menu, paw.ui.views | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [runtime/lua/paw/views/panels_mouse.lua](../../../../../../runtime/lua/paw/views/panels_mouse.lua) | [runtime/lua/paw/window_menus.tl](../../../../../../runtime/lua/paw/window_menus.tl) | Invokes supplied callback: require("paw.window_menus") | teal |
