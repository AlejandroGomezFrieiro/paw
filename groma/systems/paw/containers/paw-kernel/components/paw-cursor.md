---
type: C4 Component
title: Cursor
status: stable
groma:
  id: paw-cursor
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/cursor.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.state_get, paw.api.state_set | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.rows | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.motion_for | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callbacks: paw.lanes.any_open, paw.lanes.shown | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.track | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.current, paw.seats.keep | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.focused | teal |
| [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.round, require("paw.util") | teal |
