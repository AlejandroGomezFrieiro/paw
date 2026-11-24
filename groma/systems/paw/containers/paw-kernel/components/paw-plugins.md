---
type: C4 Component
title: Plugins
status: stable
groma:
  id: paw-plugins
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/plugins.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_note_names, paw.api.device_restart, paw.api.plugins_add_dir, paw.api.plugins_attach, paw.api.plugins_remove_dir | teal |
| [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.log, paw.api.now | teal |
| [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.owner | teal |
| [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.on | teal |
