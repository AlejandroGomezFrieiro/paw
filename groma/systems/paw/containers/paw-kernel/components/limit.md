---
type: C4 Component
title: Limit
status: stable
groma:
  id: limit
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/limit.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api.limit_async, require("paw.api") | teal |
| [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.limit_hook, paw.api.limit_watch, paw.api.real_ms | teal |
| [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.try | teal |
| [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
