---
type: C4 Component
title: Health
status: stable
groma:
  id: health
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/health.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_types | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callback: paw.api.engine_get | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [crates/paw-core/src/api/midi.rs](../../../../../../crates/paw-core/src/api/midi.rs) | Invokes supplied callback: paw.api.midi_inputs | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api.limit_async, paw.api.version | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.ui_attached, paw.api.ui_caps | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.which | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.owner | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callback: require("paw.derived") | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.undeclared | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.list | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.software_advice, paw.frontend.window_renderer | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.version | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/lang.tl](../../../../../../runtime/lua/paw/lang.tl) | Invokes supplied callback: paw.lang.problems | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callback: paw.limit.named | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.page | teal |
