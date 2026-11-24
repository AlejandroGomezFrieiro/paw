---
type: C4 Component
title: Nest
status: stable
groma:
  id: paw-nest
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/nest.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points, paw.api.lane_set_points | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add, paw.api.clip_get, paw.api.clip_notes, paw.api.clip_remove, paw.api.clip_set | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.nest_add, paw.api.nest_get, paw.api.nest_list, paw.api.nest_promote, paw.api.nest_save, paw.api.nest_set, paw.api.nest_unique, paw.api.track_add, paw.api.track_list, paw.api.track_remove, paw.api.track_set | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.signature_remove, paw.api.signature_set, paw.api.tempo_at, paw.api.tempo_bar_of, paw.api.tempo_points, paw.api.tempo_set_points, paw.api.tempo_signature | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.define, paw.commands.run, require("paw.commands") | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.add, paw.groups.members | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers, paw.markers.add, paw.markers.list, paw.markers.path, paw.markers.region, paw.markers.regions, paw.markers.remove, paw.markers.set | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.time | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, require("paw.options") | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope.bar_offset, paw.scope.breadcrumb, paw.scope.current, paw.scope.enter, paw.scope.name, paw.scope.nest, paw.scope.nest_time, paw.scope.span, paw.scope.tracks, paw.scope.widen | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callback: paw.track_kinds | teal |
| [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
