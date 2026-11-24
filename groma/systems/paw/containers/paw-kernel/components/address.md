---
type: C4 Component
title: Address
status: stable
groma:
  id: address
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/address.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.lane_get | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add, paw.api.clip_controls, paw.api.clip_get, paw.api.clip_list, paw.api.clip_remove | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_add, paw.api.device_get, paw.api.device_remove, paw.api.device_set_param | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_remove, paw.api.track_set | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callback: paw.api.tempo_points | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, paw.events.pattern, require("paw.events") | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.changed, paw.events.kernel.project_loaded, paw.events.kernel.render_done, require("paw.events.kernel") | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers, paw.markers.list | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.clip | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | Invokes supplied callbacks: paw.render, paw.render.before, paw.render.finished, require("paw.render") | teal |
| [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.merge, require("paw.util") | teal |
