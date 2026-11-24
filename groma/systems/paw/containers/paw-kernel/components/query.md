---
type: C4 Component
title: Query
status: stable
groma:
  id: query
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/query.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_controls | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.device, paw.address.lane, paw.address.marker, paw.address.note, paw.address.project, paw.address.track, require("paw.address") | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/attr.tl](../../../../../../runtime/lua/paw/attr.tl) | Invokes supplied callback: paw.attr.describe | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | Invokes supplied callbacks: paw.ex, paw.ex.fields | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.choose_clips, paw.frontend.choose_notes | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callbacks: paw.lanes, paw.lanes.name | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers, paw.markers.label, paw.markers.list | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.MusicModule, paw.music.name, require("paw.music") | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callbacks: paw.qf.go, paw.qf.set | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/query/tree.tl](../../../../../../runtime/lua/paw/query/tree.tl) | Invokes supplied callbacks: paw.query.tree.tree, require("paw.query.tree") | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/regex.tl](../../../../../../runtime/lua/paw/regex.tl) | Invokes supplied callback: paw.regex.try | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope, paw.scope.tracks | teal |
