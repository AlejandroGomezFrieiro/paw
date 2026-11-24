---
type: C4 Component
title: Pickers
status: stable
groma:
  id: pickers
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/pickers.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/pickers.lua](../../../../../../runtime/lua/paw/defaults/pickers.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.plugins_rescan | teal |
| [runtime/lua/paw/defaults/pickers.lua](../../../../../../runtime/lua/paw/defaults/pickers.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.log | teal |
| [runtime/lua/paw/defaults/pickers.lua](../../../../../../runtime/lua/paw/defaults/pickers.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/defaults/pickers.lua](../../../../../../runtime/lua/paw/defaults/pickers.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.get | teal |
| [runtime/lua/paw/defaults/pickers.lua](../../../../../../runtime/lua/paw/defaults/pickers.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callback: require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/pickers.lua](../../../../../../runtime/lua/paw/defaults/pickers.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.on | teal |
| [runtime/lua/paw/defaults/pickers.lua](../../../../../../runtime/lua/paw/defaults/pickers.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callbacks: paw.pick, paw.pick.resume, paw.pick.sources | teal |
| [runtime/lua/paw/defaults/pickers.lua](../../../../../../runtime/lua/paw/defaults/pickers.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
