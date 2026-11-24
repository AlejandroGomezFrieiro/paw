---
type: C4 Component
title: Devices
status: stable
groma:
  id: act-devices
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/act/devices.tl
      symbol: param_of
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/act/devices.tl](../../../../../../runtime/lua/paw/frontend/act/devices.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_move, paw.api.device_restart, paw.api.device_set, paw.api.device_set_param | teal |
| [runtime/lua/paw/frontend/act/devices.tl](../../../../../../runtime/lua/paw/frontend/act/devices.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/act/devices.tl](../../../../../../runtime/lua/paw/frontend/act/devices.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/frontend/act/devices.tl](../../../../../../runtime/lua/paw/frontend/act/devices.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callback: require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/act/devices.tl](../../../../../../runtime/lua/paw/frontend/act/devices.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.paw, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/act/devices.tl](../../../../../../runtime/lua/paw/frontend/act/devices.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, require("paw.util") | teal |
