---
type: C4 Component
title: Fx
status: stable
groma:
  id: fx
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/fx.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_call, paw.api.device_editor, paw.api.device_get, paw.api.device_load, paw.api.device_set, paw.api.device_set_param | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api.decode, paw.api.encode | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_attached | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.through, paw.audition.try | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/device_presets.lua](../../../../../../runtime/lua/paw/device_presets.lua) | Invokes supplied callback: require("paw.device_presets") | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.on | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.format_value | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.rows | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.device_types | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.set | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.device, paw.objects.restore_device, paw.objects.track | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | Invokes supplied callback: paw.params.preset_value | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callbacks: paw.pick, paw.pick.match | teal |
| [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.input, paw.ui.notify, paw.ui.views | teal |
