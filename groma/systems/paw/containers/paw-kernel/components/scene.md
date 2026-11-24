---
type: C4 Component
title: Scene
status: stable
groma:
  id: scene
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/scene.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callback: paw.api.engine_get | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_encode | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callback: paw.api.rpc_push | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.canvas_pixels, paw.api.ui_redraws | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.log, paw.api.now | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [crates/paw-core/src/scene.rs](../../../../../../crates/paw-core/src/scene.rs) | Invokes supplied callbacks: paw.api.scene_blob, paw.api.scene_end, paw.api.scene_forget, paw.api.scene_roles | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | Invokes supplied callbacks: paw.audio.level, paw.audio.levels, paw.audio.load | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.cell, paw.canvas.open_views, paw.canvas.palette, paw.canvas.pointer, paw.canvas.windows | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.track_peak | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.transport_play, require("paw.events.kernel") | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.bind, paw.layout.find_id, paw.layout.settle | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | Invokes supplied callbacks: paw.panes.pointer, paw.panes.state | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | Invokes supplied callbacks: paw.roles.input, paw.roles.version | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.within | teal |
| [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui, paw.ui.views | teal |
