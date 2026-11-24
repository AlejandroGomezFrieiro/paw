---
type: C4 Component
title: Params
status: stable
groma:
  id: params
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/params.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_call, paw.api.device_get | teal |
| [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | [runtime/lua/paw/device_presets.lua](../../../../../../runtime/lua/paw/device_presets.lua) | Invokes supplied callback: require("paw.device_presets") | teal |
| [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callback: paw.fx.load | teal |
