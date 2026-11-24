---
type: C4 Component
title: Learn
status: stable
groma:
  id: learn
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/learn.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set_param | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_set | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_set | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.run | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | Invokes supplied callbacks: paw.params.fraction, paw.params.from_fraction | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.notify, paw.ui.views | teal |
