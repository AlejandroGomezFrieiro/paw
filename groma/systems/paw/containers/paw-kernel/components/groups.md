---
type: C4 Component
title: Groups
status: stable
groma:
  id: groups
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/groups.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_move, paw.api.track_remove, paw.api.track_set | teal |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, paw.events.pattern, paw.events.stamp, require("paw.events") | teal |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.track_removed, require("paw.events.kernel") | teal |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | Invokes supplied callbacks: paw.folds, paw.folds.collapse, paw.folds.group_closed, paw.folds.set_group | teal |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callback: paw.lanes.lines | teal |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.add_track | teal |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope, paw.scope.group, paw.scope.tracks | teal |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, require("paw.util") | teal |
| [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | Invokes supplied callback: paw.vca.is_vca | teal |
