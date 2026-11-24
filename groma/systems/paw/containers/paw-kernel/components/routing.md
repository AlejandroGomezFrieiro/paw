---
type: C4 Component
title: Routing
status: stable
groma:
  id: routing
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/act/routing.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/act/routing.tl](../../../../../../runtime/lua/paw/frontend/act/routing.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set | teal |
| [runtime/lua/paw/frontend/act/routing.tl](../../../../../../runtime/lua/paw/frontend/act/routing.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/act/routing.tl](../../../../../../runtime/lua/paw/frontend/act/routing.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_set | teal |
| [runtime/lua/paw/frontend/act/routing.tl](../../../../../../runtime/lua/paw/frontend/act/routing.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callback: require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/act/routing.tl](../../../../../../runtime/lua/paw/frontend/act/routing.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.paw, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/act/routing.tl](../../../../../../runtime/lua/paw/frontend/act/routing.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/frontend/act/routing.tl](../../../../../../runtime/lua/paw/frontend/act/routing.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fader_db, require("paw.util") | teal |
