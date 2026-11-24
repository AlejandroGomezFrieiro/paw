---
type: C4 Component
title: Effect windows
status: stable
groma:
  id: effect-windows
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/effect_windows.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set_param | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callback: paw.canvas.open | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.set_track, paw.cursor.track | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.mix | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.menus | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | Invokes supplied callbacks: paw.params.format, paw.params.read | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.keep | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callbacks: paw.theme.palette, require("paw.theme") | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.notify, paw.ui.show, paw.ui.view, paw.ui.views | teal |
| [runtime/lua/paw/views/effect_windows.lua](../../../../../../runtime/lua/paw/views/effect_windows.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
