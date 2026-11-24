---
type: C4 Component
title: Lanes
status: stable
groma:
  id: defaults-lanes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/lanes.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_get, paw.api.lane_list, paw.api.lane_points | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.lane_id, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callback: require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.pan_text | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.act, paw.frontend.format_value | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.classic, paw.keymap.group, paw.keymap.human, paw.keymap.operator | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callbacks: paw.lanes.edit, paw.lanes.format, paw.lanes.name, paw.lanes.open, paw.lanes.param_of, paw.lanes.point_at, paw.lanes.step, paw.lanes.toggle, paw.lanes.value_at | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.device, paw.objects.lane, paw.objects.time | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.ask_value, paw.ui.focus, paw.ui.notify | teal |
| [runtime/lua/paw/defaults/lanes.lua](../../../../../../runtime/lua/paw/defaults/lanes.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge, paw.util.round | teal |
