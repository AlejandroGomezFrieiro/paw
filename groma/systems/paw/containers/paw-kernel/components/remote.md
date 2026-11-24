---
type: C4 Component
title: Remote
status: stable
groma:
  id: remote
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/remote.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_encode | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callbacks: paw.api.rpc_clients, paw.api.rpc_push, paw.api.ui_client, paw.api.ui_detach | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraws | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.define, require("paw.commands") | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, paw.events.pattern, require("paw.events") | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.transport_play, require("paw.events.kernel") | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.state | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | Invokes supplied callbacks: paw.scene, paw.scene.set_pace, paw.scene.sync | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.close, paw.seats.enter, paw.seats.has, paw.seats.open, paw.seats.within, require("paw.seats") | teal |
| [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.active, paw.ui.notify | teal |
