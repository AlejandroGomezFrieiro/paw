---
type: C4 Component
title: Takes
status: stable
groma:
  id: takes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/takes.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_get, paw.api.clip_list, paw.api.clip_notes, paw.api.clip_remove, paw.api.clip_set, paw.api.clip_set_controls, paw.api.clip_set_notes | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.state_get, paw.api.state_set | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.Context, paw.commands.Result, paw.commands.define, require("paw.commands") | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.clip, paw.cursor.track_id | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.arrange | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.track_removed, require("paw.events.kernel") | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.selection, paw.keymap.set_mode | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callback: paw.lanes.changed | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.restore_clip | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | Invokes supplied callbacks: paw.stretch.carry, paw.stretch.file_seconds, paw.stretch.moved | teal |
| [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
