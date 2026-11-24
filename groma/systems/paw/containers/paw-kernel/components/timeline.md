---
type: C4 Component
title: Timeline
status: stable
groma:
  id: timeline
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/act/timeline.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/act/timeline.tl](../../../../../../runtime/lua/paw/frontend/act/timeline.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/act/timeline.tl](../../../../../../runtime/lua/paw/frontend/act/timeline.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/frontend/act/timeline.tl](../../../../../../runtime/lua/paw/frontend/act/timeline.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/frontend/act/timeline.tl](../../../../../../runtime/lua/paw/frontend/act/timeline.tl) | [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | Invokes supplied callbacks: paw.frontend.act.clips.set_pointing, require("paw.frontend.act.clips") | teal |
| [runtime/lua/paw/frontend/act/timeline.tl](../../../../../../runtime/lua/paw/frontend/act/timeline.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callbacks: paw.frontend.core.act, require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/act/timeline.tl](../../../../../../runtime/lua/paw/frontend/act/timeline.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.paw, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/act/timeline.tl](../../../../../../runtime/lua/paw/frontend/act/timeline.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/frontend/act/timeline.tl](../../../../../../runtime/lua/paw/frontend/act/timeline.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: require("paw.util") | teal |
