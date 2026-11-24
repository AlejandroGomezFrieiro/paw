---
type: C4 Component
title: Recent
status: stable
groma:
  id: recent
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/recent.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.open | teal |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.project | teal |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callbacks: paw.pick, paw.pick.sources | teal |
| [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
