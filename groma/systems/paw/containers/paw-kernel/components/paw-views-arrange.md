---
type: C4 Component
title: Arrange
status: stable
groma:
  id: paw-views-arrange
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/arrange.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points, paw.api.lane_value_at | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_playhead | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.get | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.lane_id, paw.cursor.master_reachable, paw.cursor.row, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callbacks: paw.derived.visible, require("paw.derived") | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.bar_lines, paw.draw.curve, paw.draw.g, paw.draw.hue, paw.draw.jump_scroll, paw.draw.meter, paw.draw.track_colour, paw.draw.track_hue | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/folds.tl](../../../../../../runtime/lua/paw/folds.tl) | Invokes supplied callback: paw.folds.time_map | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.band_state, paw.frontend.chosen_clips, paw.frontend.take_rows | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.rows | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.human, paw.keymap.jump_serial, paw.keymap.mode, paw.keymap.selection | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callbacks: paw.lanes.any_open, paw.lanes.format, paw.lanes.is_open, paw.lanes.lines, paw.lanes.name, paw.lanes.shown, paw.lanes.value_at | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/nest.tl](../../../../../../runtime/lua/paw/nest.tl) | Invokes supplied callback: paw.nest.shift | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | Invokes supplied callback: paw.roles.registry | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | Invokes supplied callbacks: paw.ruler.draw_lanes, paw.ruler.label, paw.ruler.lane_rows | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope.format, paw.scope.span | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.fields | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | Invokes supplied callbacks: paw.takes.lane_count, paw.takes.of | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.is_bar_line, paw.tempo.marks | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | Invokes supplied callbacks: paw.tempolane.range, paw.tempolane.shown | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callback: require("paw.theme") | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/trackcolumn.tl](../../../../../../runtime/lua/paw/trackcolumn.tl) | Invokes supplied callbacks: paw.trackcolumn.draw, paw.trackcolumn.layout | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.layers, paw.ui.paint, paw.ui.scene_drawing, paw.ui.transport, paw.ui.view | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit, paw.util.wrap | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/views/arrange_track.tl](../../../../../../runtime/lua/paw/views/arrange_track.tl) | Invokes supplied callbacks: paw.views.arrange_track.clip_props, paw.views.arrange_track.header, paw.views.arrange_track.level_glyph, require("paw.views.arrange_track") | teal |
| [runtime/lua/paw/views/arrange.tl](../../../../../../runtime/lua/paw/views/arrange.tl) | [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | Invokes supplied callbacks: paw.vzoom.any_own, paw.vzoom.lane_rows, paw.vzoom.rows_of, paw.vzoom.track_rows | teal |
