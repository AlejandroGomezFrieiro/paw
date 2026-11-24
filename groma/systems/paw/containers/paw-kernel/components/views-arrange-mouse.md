---
type: C4 Component
title: Arrange mouse
status: stable
groma:
  id: views-arrange-mouse
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/arrange_mouse.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_get, paw.api.lane_points | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.set_track, paw.cursor.snap | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.clear_peak, paw.draw.db_text, paw.draw.g, paw.draw.track_colour, paw.draw.track_hue | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.act, paw.frontend.chosen_clips, paw.frontend.lane_span | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.is_group, paw.groups.rows | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.selection | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callback: paw.lanes.format | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers, paw.markers.label, paw.markers.lane_row, paw.markers.list | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/mouse_menus.tl](../../../../../../runtime/lua/paw/mouse_menus.tl) | Invokes supplied callbacks: paw.mouse_menus.clip, paw.mouse_menus.lane, paw.mouse_menus.marker, paw.mouse_menus.selection, paw.mouse_menus.takes, paw.mouse_menus.tempo_lane, paw.mouse_menus.tempo_mark, paw.mouse_menus.timeline, paw.mouse_menus.track, paw.mouse_menus.warp, require("paw.mouse_menus") | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.gesture, paw.mouse.grab, paw.mouse.has, paw.mouse.hint, paw.mouse.mode, paw.mouse.wheel | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | Invokes supplied callback: paw.takes.comp | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.at, paw.tempo.is_bar_line, paw.tempo.marks | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | Invokes supplied callbacks: paw.tempolane.bpm, paw.tempolane.fraction, paw.tempolane.points | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/trackcolumn.tl](../../../../../../runtime/lua/paw/trackcolumn.tl) | Invokes supplied callbacks: paw.trackcolumn.click, paw.trackcolumn.shows | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.menu, paw.ui.views | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.round | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/vzoom.tl](../../../../../../runtime/lua/paw/vzoom.tl) | Invokes supplied callback: paw.vzoom.step | teal |
| [runtime/lua/paw/views/arrange_mouse.tl](../../../../../../runtime/lua/paw/views/arrange_mouse.tl) | [runtime/lua/paw/window_menus.tl](../../../../../../runtime/lua/paw/window_menus.tl) | Invokes supplied callback: require("paw.window_menus") | teal |
