---
type: C4 Component
title: Tracks
status: stable
groma:
  id: act-tracks
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/act/tracks.tl
      symbol: nth
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/act/tracks.tl](../../../../../../runtime/lua/paw/frontend/act/tracks.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.automation_hold | teal |
| [runtime/lua/paw/frontend/act/tracks.tl](../../../../../../runtime/lua/paw/frontend/act/tracks.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/act/tracks.tl](../../../../../../runtime/lua/paw/frontend/act/tracks.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_move, paw.api.track_set | teal |
| [runtime/lua/paw/frontend/act/tracks.tl](../../../../../../runtime/lua/paw/frontend/act/tracks.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.exec, require("paw.commands") | teal |
| [runtime/lua/paw/frontend/act/tracks.tl](../../../../../../runtime/lua/paw/frontend/act/tracks.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callbacks: paw.frontend.core.act, require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/act/tracks.tl](../../../../../../runtime/lua/paw/frontend/act/tracks.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.devices, paw.frontend.host.paw, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/act/tracks.tl](../../../../../../runtime/lua/paw/frontend/act/tracks.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fader_db, require("paw.util") | teal |
