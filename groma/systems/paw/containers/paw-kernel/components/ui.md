---
type: C4 Component
title: Ui
status: stable
groma:
  id: ui
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/ui.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.grid_keep, paw.api.grid_live_begin, paw.api.grid_live_end, paw.api.grid_live_keep, paw.api.grid_live_restore, paw.api.grid_live_seal, paw.api.grid_live_still, paw.api.grid_put, paw.api.grid_surface, paw.api.grid_surface_ops, paw.api.grid_surfaces_seal, paw.api.str_width, paw.api.ui_attached, paw.api.ui_caps, paw.api.ui_frames, paw.api.ui_mouse, paw.api.ui_redraw, paw.api.ui_redraw_live, paw.api.ui_size | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.log, paw.api.now | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callbacks: paw.api.transport_get, paw.api.transport_playhead | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [crates/paw-core/src/scene.rs](../../../../../../crates/paw-core/src/scene.rs) | Invokes supplied callbacks: paw.api.scene_begin, paw.api.scene_close, paw.api.scene_draw, paw.api.scene_open, paw.api.scene_picture | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/buf.tl](../../../../../../runtime/lua/paw/buf.tl) | Invokes supplied callbacks: paw.buf.fill, paw.buf.text, require("paw.buf") | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.close, paw.canvas.draw, paw.canvas.inside, paw.canvas.open_views, paw.canvas.paint | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callbacks: paw.derived.frame_end, paw.derived.frame_start, require("paw.derived") | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.keys, paw.draw.meters_falling, paw.draw.term_def, paw.draw.track_peak, paw.draw.truecolor, paw.draw.use_glyphs | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, paw.events.stamp, require("paw.events") | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, paw.events.kernel.track_added, paw.events.kernel.track_changed, paw.events.kernel.track_removed, paw.events.kernel.transport_play, paw.events.kernel.transport_stop, require("paw.events.kernel") | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.back, paw.layout.bind, paw.layout.border_at, paw.layout.bound, paw.layout.close, paw.layout.conceal, paw.layout.copy_tabs, paw.layout.current, paw.layout.default_tree, paw.layout.dock, paw.layout.drag_border, paw.layout.enter, paw.layout.find, paw.layout.find_id, paw.layout.homes, paw.layout.instance_of, paw.layout.instances, paw.layout.min_width, paw.layout.one_window, paw.layout.reveal, paw.layout.settle, paw.layout.show_in, paw.layout.shown, paw.layout.tab_go, paw.layout.tab_title, paw.layout.time_follow, paw.layout.time_lead, paw.layout.window_fields, paw.layout.windows, paw.layout.within, require("paw.layout") | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.done, paw.mouse.gesture, paw.mouse.grab, paw.mouse.take, paw.mouse.to_surface | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | Invokes supplied callbacks: paw.panes, paw.panes.cells | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/remote.tl](../../../../../../runtime/lua/paw/remote.tl) | Invokes supplied callbacks: paw.remote, paw.remote.wake | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | Invokes supplied callbacks: paw.roles.begin, paw.roles.finish, paw.roles.pointer | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/scene.tl](../../../../../../runtime/lua/paw/scene.tl) | Invokes supplied callbacks: paw.scene, paw.scene.wake | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.current, paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | Invokes supplied callbacks: paw.statusline, paw.statusline.tabline, paw.statusline.tabline_always, paw.statusline.winbar | teal |
| [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fit, require("paw.util") | teal |
