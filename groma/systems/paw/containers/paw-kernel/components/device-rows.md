---
type: C4 Component
title: Device rows
status: stable
groma:
  id: device-rows
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/device_rows.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set_param | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.run | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.format_value | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.classic, paw.keymap.getreg, paw.keymap.human, paw.keymap.operator, paw.keymap.setreg | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.current, paw.layout.find, paw.layout.within | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.device, paw.objects.restore_device | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | Invokes supplied callback: paw.params.step | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | Invokes supplied callback: paw.routes.sidechain_text | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.layout, paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/device_rows.lua](../../../../../../runtime/lua/paw/device_rows.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
