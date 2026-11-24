---
type: C4 Component
title: Shada
status: stable
groma:
  id: shada
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/shada.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.changed, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id, require("paw.cursor") | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.exit, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.within | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.focused, paw.ui.views | teal |
| [runtime/lua/paw/shada.tl](../../../../../../runtime/lua/paw/shada.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.Data, require("paw.util") | teal |
