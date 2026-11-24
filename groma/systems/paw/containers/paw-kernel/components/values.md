---
type: C4 Component
title: Values
status: stable
groma:
  id: values
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/values.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/values.lua](../../../../../../runtime/lua/paw/defaults/values.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set_param | teal |
| [runtime/lua/paw/defaults/values.lua](../../../../../../runtime/lua/paw/defaults/values.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.beat | teal |
| [runtime/lua/paw/defaults/values.lua](../../../../../../runtime/lua/paw/defaults/values.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callback: require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/values.lua](../../../../../../runtime/lua/paw/defaults/values.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.pan_text | teal |
| [runtime/lua/paw/defaults/values.lua](../../../../../../runtime/lua/paw/defaults/values.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.format_value | teal |
| [runtime/lua/paw/defaults/values.lua](../../../../../../runtime/lua/paw/defaults/values.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/defaults/values.lua](../../../../../../runtime/lua/paw/defaults/values.lua) | [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | Invokes supplied callbacks: paw.tempolane.add, paw.tempolane.point_at | teal |
| [runtime/lua/paw/defaults/values.lua](../../../../../../runtime/lua/paw/defaults/values.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.ask_value, paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/defaults/values.lua](../../../../../../runtime/lua/paw/defaults/values.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.round | teal |
