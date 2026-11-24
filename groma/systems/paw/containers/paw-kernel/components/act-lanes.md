---
type: C4 Component
title: Lanes
status: stable
groma:
  id: act-lanes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/act/lanes.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/act/lanes.tl](../../../../../../runtime/lua/paw/frontend/act/lanes.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_add, paw.api.lane_add_point, paw.api.lane_get, paw.api.lane_list, paw.api.lane_points, paw.api.lane_set, paw.api.lane_set_points | teal |
| [runtime/lua/paw/frontend/act/lanes.tl](../../../../../../runtime/lua/paw/frontend/act/lanes.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/act/lanes.tl](../../../../../../runtime/lua/paw/frontend/act/lanes.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callbacks: paw.frontend.core.act, paw.frontend.core.lane_span, require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/act/lanes.tl](../../../../../../runtime/lua/paw/frontend/act/lanes.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.Point, paw.frontend.host.paw, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/act/lanes.tl](../../../../../../runtime/lua/paw/frontend/act/lanes.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/frontend/act/lanes.tl](../../../../../../runtime/lua/paw/frontend/act/lanes.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, require("paw.util") | teal |
