---
type: C4 Component
title: Mixer rows
status: stable
groma:
  id: mixer-rows
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/mixer_rows.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_editor, paw.api.device_get | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_set | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callback: paw.address.lane | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.master_reachable, paw.cursor.row, paw.cursor.set_track, paw.cursor.track, paw.cursor.track_id | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.db_text | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.arrange | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.act | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.rows | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.getreg, paw.keymap.operator, paw.keymap.setreg | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.device, paw.objects.restore_device, paw.objects.track | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.ask_value, paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/mixer_rows.lua](../../../../../../runtime/lua/paw/mixer_rows.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fader_db, paw.util.merge, paw.util.round | teal |
