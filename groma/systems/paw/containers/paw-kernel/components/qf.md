---
type: C4 Component
title: Qf
status: stable
groma:
  id: qf
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/qf.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.lane_get | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list, paw.api.media_missing, paw.api.media_search | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_restart | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.log | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.edit, paw.address.parse, paw.address.project, paw.address.render, paw.address.resolve, paw.address.schemes, paw.address.track, paw.address.track_of, require("paw.address") | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.Context, paw.commands.Result, paw.commands.alias, paw.commands.define, paw.commands.exec, require("paw.commands") | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | Invokes supplied callbacks: paw.diagnostic.changed, paw.diagnostic.get, paw.diagnostic.where | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.changed, paw.events.kernel.clip_added, paw.events.kernel.device_added, paw.events.kernel.device_changed, paw.events.kernel.device_invalid, paw.events.kernel.device_ready, paw.events.kernel.device_removed, paw.events.kernel.device_stopped, paw.events.kernel.project_loaded, paw.events.kernel.render_done, paw.events.kernel.render_failed, require("paw.events.kernel") | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callbacks: paw.lanes.name, paw.lanes.open | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | Invokes supplied callbacks: paw.render, paw.render.before, paw.render.finished, require("paw.render") | teal |
| [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.go, paw.ui.locators, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
