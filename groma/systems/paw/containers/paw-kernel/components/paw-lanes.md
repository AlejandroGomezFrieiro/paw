---
type: C4 Component
title: Lanes
status: stable
groma:
  id: paw-lanes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/lanes.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_get, paw.api.lane_list, paw.api.lane_points, paw.api.lane_set_points, paw.api.lane_value_at | teal |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.state_get, paw.api.state_set | teal |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.pan_text | teal |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.track_removed, require("paw.events.kernel") | teal |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.format_value | teal |
| [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.rows | teal |
