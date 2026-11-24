---
type: C4 Component
title: Tracks
status: stable
groma:
  id: tracks
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/tracks.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | Invokes supplied callbacks: paw.audio.choices, paw.audio.choose, paw.audio.label, paw.audio.pick | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.index, paw.cursor.on_master, paw.cursor.set_track, paw.cursor.track, paw.cursor.track_id | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callback: require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | Invokes supplied callbacks: paw.folds.all, paw.folds.clear, paw.folds.close, paw.folds.delete, paw.folds.describe, paw.folds.level, paw.folds.name, paw.folds.open, paw.folds.toggle | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.act, paw.frontend.routing | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callback: paw.fx.preferred | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.add, paw.groups.dissolve, paw.groups.is_group, paw.groups.link, paw.groups.linked, paw.groups.make, paw.groups.of, paw.groups.remove, paw.groups.rows | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.selection, paw.keymap.set_mode | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | Invokes supplied callback: paw.nest.toggle | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.midi, paw.objects.tracks | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | Invokes supplied callback: paw.routes.peers | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callback: paw.scope.tracks | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callback: require("paw.theme") | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callbacks: paw.track_kinds.add, paw.track_kinds.kinds, paw.track_kinds.list | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.notify | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fader_db, paw.util.round | teal |
| [runtime/lua/paw/defaults/tracks.lua](../../../../../../runtime/lua/paw/defaults/tracks.lua) | [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | Invokes supplied callbacks: paw.vca.assign, paw.vca.dissolve, paw.vca.is_vca, paw.vca.list, paw.vca.make, paw.vca.unassign | teal |
