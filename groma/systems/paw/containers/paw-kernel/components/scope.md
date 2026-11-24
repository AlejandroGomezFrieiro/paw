---
type: C4 Component
title: Scope
status: stable
groma:
  id: scope
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/scope.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.engine_audible, paw.api.engine_held, paw.api.engine_hold | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_screen | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.nest_list, paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.nest_beat, paw.api.nest_own_tempo, paw.api.nest_song_beat, paw.api.nest_tempo_at, paw.api.nest_tempo_bar_length, paw.api.nest_tempo_bar_of, paw.api.nest_tempo_bar_start, paw.api.nest_tempo_bbt, paw.api.nest_tempo_from_bbt, paw.api.nest_tempo_is_bar_line, paw.api.nest_tempo_points, paw.api.nest_tempo_seconds, paw.api.nest_tempo_signature, paw.api.tempo_bar_of, paw.api.tempo_bar_start, paw.api.tempo_bbt | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.define, paw.commands.run, require("paw.commands") | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, paw.events.stamp, require("paw.events") | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.clip_added, paw.events.kernel.clip_changed, paw.events.kernel.clip_removed, paw.events.kernel.device_added, paw.events.kernel.device_changed, paw.events.kernel.device_removed, paw.events.kernel.lane_added, paw.events.kernel.lane_changed, paw.events.kernel.lane_removed, paw.events.kernel.project_loaded, paw.events.kernel.render_cancelled, paw.events.kernel.render_done, paw.events.kernel.render_failed, paw.events.kernel.track_added, paw.events.kernel.track_changed, paw.events.kernel.track_moved, paw.events.kernel.track_removed, require("paw.events.kernel") | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | Invokes supplied callbacks: paw.folds.closed_at, paw.folds.list, paw.folds.name, paw.folds.row, paw.folds.time_at | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | Invokes supplied callbacks: paw.freeze.render_opts, paw.freeze.state | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.refresh | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers, paw.markers.children, paw.markers.label, paw.markers.list, paw.markers.parent, paw.markers.path, paw.markers.region, paw.markers.regions, paw.markers.walk | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.time, paw.objects.transport | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | Invokes supplied callback: paw.render | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/routes.lua](../../../../../../runtime/lua/paw/routes.lua) | Invokes supplied callback: paw.routes.reached | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | Invokes supplied callback: paw.textbuf.sync | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.drawing_win, paw.ui.focus, paw.ui.input, paw.ui.notify, paw.ui.tab, paw.ui.tabs, paw.ui.views | teal |
| [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | Invokes supplied callback: paw.vca.is_vca | teal |
