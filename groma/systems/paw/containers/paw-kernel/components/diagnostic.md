---
type: C4 Component
title: Diagnostic
status: stable
groma:
  id: diagnostic
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/diagnostic.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.device, paw.address.edit, paw.address.find_note, paw.address.note, paw.address.of, paw.address.param, paw.address.parse, paw.address.project, paw.address.track, paw.address.track_of, paw.address.within, require("paw.address") | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callback: paw.qf.diagnostics | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/trackcolumn.tl](../../../../../../runtime/lua/paw/trackcolumn.tl) | Invokes supplied callback: paw.trackcolumn.sign | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.go, paw.ui.layer, paw.ui.locators, paw.ui.notify, paw.ui.views, paw.ui.visible | teal |
| [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fit, paw.util.merge, require("paw.util") | teal |
