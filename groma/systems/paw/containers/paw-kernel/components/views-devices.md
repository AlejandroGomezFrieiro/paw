---
type: C4 Component
title: Devices
status: stable
groma:
  id: views-devices
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/devices.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_value_at | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set_param | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.format_value, paw.frontend.revision, paw.frontend.routing | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callback: paw.fx.host_params | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.alive, paw.layout.bound, paw.layout.current | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.device, paw.objects.track | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | Invokes supplied callbacks: paw.params.fraction, paw.params.step | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | Invokes supplied callback: paw.routes.sidechain_text | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.current, paw.seats.fields | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.drawing_win, paw.ui.float, paw.ui.focused, paw.ui.notify, paw.ui.paint, paw.ui.titlebar, paw.ui.view | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [runtime/lua/paw/views/devices.lua](../../../../../../runtime/lua/paw/views/devices.lua) | [runtime/lua/paw/views/device_pictures.lua](../../../../../../runtime/lua/paw/views/device_pictures.lua) | Invokes supplied callback: require("paw.views.device_pictures") | teal |
