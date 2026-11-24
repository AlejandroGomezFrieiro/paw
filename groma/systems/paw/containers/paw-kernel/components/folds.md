---
type: C4 Component
title: Folds
status: stable
groma:
  id: folds
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/folds.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.is_group, paw.groups.members, paw.groups.of, paw.groups.rows | teal |
| [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers, paw.markers.find, paw.markers.path, paw.markers.walk | teal |
| [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope.current, paw.scope.holder, paw.scope.limits_tracks, paw.scope.span, paw.scope.tracks, paw.scope.window | teal |
