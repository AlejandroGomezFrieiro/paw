---
type: C4 Component
title: Loading
status: stable
groma:
  id: loading
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/loading.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_load | teal |
| [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.master, paw.objects.tracks | teal |
| [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.views | teal |
