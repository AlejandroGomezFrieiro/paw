---
type: C4 Component
title: Devices
status: stable
groma:
  id: defaults-devices
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/devices.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/devices.lua](../../../../../../runtime/lua/paw/defaults/devices.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_editor | teal |
| [runtime/lua/paw/defaults/devices.lua](../../../../../../runtime/lua/paw/defaults/devices.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.completers | teal |
| [runtime/lua/paw/defaults/devices.lua](../../../../../../runtime/lua/paw/defaults/devices.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track | teal |
| [runtime/lua/paw/defaults/devices.lua](../../../../../../runtime/lua/paw/defaults/devices.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callback: require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/devices.lua](../../../../../../runtime/lua/paw/defaults/devices.lua) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callback: paw.fx.add | teal |
| [runtime/lua/paw/defaults/devices.lua](../../../../../../runtime/lua/paw/defaults/devices.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.device_types | teal |
| [runtime/lua/paw/defaults/devices.lua](../../../../../../runtime/lua/paw/defaults/devices.lua) | [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | Invokes supplied callback: paw.mixer_rows.device | teal |
| [runtime/lua/paw/defaults/devices.lua](../../../../../../runtime/lua/paw/defaults/devices.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.midi | teal |
| [runtime/lua/paw/defaults/devices.lua](../../../../../../runtime/lua/paw/defaults/devices.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.input, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
