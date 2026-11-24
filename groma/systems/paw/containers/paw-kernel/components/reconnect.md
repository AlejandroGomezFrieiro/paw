---
type: C4 Component
title: Reconnect
status: stable
groma:
  id: reconnect
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/reconnect.lua
      symbol: reconnect
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/reconnect.lua](../../../../../../runtime/lua/paw/reconnect.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.audio_reconnect, paw.api.audio_watch, paw.api.engine_get | teal |
| [runtime/lua/paw/reconnect.lua](../../../../../../runtime/lua/paw/reconnect.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [runtime/lua/paw/reconnect.lua](../../../../../../runtime/lua/paw/reconnect.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/reconnect.lua](../../../../../../runtime/lua/paw/reconnect.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [runtime/lua/paw/reconnect.lua](../../../../../../runtime/lua/paw/reconnect.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
