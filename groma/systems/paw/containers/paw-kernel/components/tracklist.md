---
type: C4 Component
title: Tracklist
status: stable
groma:
  id: tracklist
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/tracklist.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_move, paw.api.device_remove, paw.api.device_set, paw.api.device_set_param | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_move, paw.api.track_remove, paw.api.track_set | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.tempo_bbt, paw.api.tempo_signature | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.set_beat, paw.cursor.set_track | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callbacks: paw.fx.load, paw.fx.presets | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.add, paw.groups.is_group, paw.groups.of, paw.groups.remove | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.device_types | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers.add, paw.markers.list, paw.markers.remove, paw.markers.set | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.device, paw.objects.master, paw.objects.restore_device, paw.objects.restore_track, paw.objects.time, paw.objects.track | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope.contains, paw.scope.limits_tracks, paw.scope.tracks | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | Invokes supplied callbacks: paw.textbuf.kind, paw.textbuf.open, paw.textbuf.same | teal |
| [runtime/lua/paw/views/tracklist.lua](../../../../../../runtime/lua/paw/views/tracklist.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.notify, paw.ui.show, paw.ui.views | teal |
