---
type: C4 Component
title: Curves
status: stable
groma:
  id: curves
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/curves.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_get, paw.api.lane_points, paw.api.lane_set_points, paw.api.lane_set_shapes, paw.api.lane_shapes | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_get, paw.api.clip_set_controls | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.parse, paw.address.resolve | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.format_value | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callbacks: paw.lanes.format, paw.lanes.name, paw.lanes.param_of, paw.lanes.step | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.device, paw.objects.time | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | Invokes supplied callbacks: paw.params.fraction, paw.params.from_fraction | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | Invokes supplied callback: paw.tempolane.set_points | teal |
| [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.round, require("paw.util") | teal |
