---
type: C4 Component
title: Automation
status: stable
groma:
  id: automation
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/automation.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/automation.lua](../../../../../../runtime/lua/paw/defaults/automation.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.lane_id | teal |
| [runtime/lua/paw/defaults/automation.lua](../../../../../../runtime/lua/paw/defaults/automation.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callback: require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/automation.lua](../../../../../../runtime/lua/paw/defaults/automation.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.lane, paw.objects.time | teal |
| [runtime/lua/paw/defaults/automation.lua](../../../../../../runtime/lua/paw/defaults/automation.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.notify | teal |
