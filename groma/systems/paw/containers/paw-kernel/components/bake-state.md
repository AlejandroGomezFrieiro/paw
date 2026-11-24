---
type: C4 Component
title: Bake state
status: stable
groma:
  id: bake-state
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/bake_state.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/bake_state.tl](../../../../../../runtime/lua/paw/bake_state.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points, paw.api.lane_shapes | teal |
| [runtime/lua/paw/bake_state.tl](../../../../../../runtime/lua/paw/bake_state.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [runtime/lua/paw/bake_state.tl](../../../../../../runtime/lua/paw/bake_state.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/bake_state.tl](../../../../../../runtime/lua/paw/bake_state.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/bake_state.tl](../../../../../../runtime/lua/paw/bake_state.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/bake_state.tl](../../../../../../runtime/lua/paw/bake_state.tl) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callback: require("paw.derived") | teal |
