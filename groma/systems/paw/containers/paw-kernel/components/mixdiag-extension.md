---
type: C4 Component
title: Mix diagnostics extension
status: stable
groma:
  id: mixdiag-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/mixdiag/init.lua
      symbol: try
    - scanner: teal
      file: extensions/mixdiag/lua/mixdiag/init.lua
    - scanner: teal
      file: extensions/mixdiag/lua/mixdiag/lens.lua
    - scanner: teal
      file: extensions/mixdiag/lua/mixdiag/paint.lua
    - scanner: teal
      file: extensions/mixdiag/lua/mixdiag/rules.lua
    - scanner: teal
      file: extensions/mixdiag/lua/mixdiag/view.lua
    - scanner: teal
      file: extensions/mixdiag/manifest.lua
      symbol: mixdiag
  group: Bundled extensions
  technology: Lua
description: Measures the mix and reports findings to jump to.
---

Measures loudness (LUFS), true peak and phase of the mix, and shows each problem as a finding in a list. A key in the list goes to the place of the problem.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/mixdiag/init.lua](../../../../../../extensions/mixdiag/init.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [extensions/mixdiag/init.lua](../../../../../../extensions/mixdiag/init.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.selection, paw.keymap.set_mode | teal |
| [extensions/mixdiag/init.lua](../../../../../../extensions/mixdiag/init.lua) | [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | Invokes supplied callbacks: paw.lsp.config, paw.lsp.enable | teal |
| [extensions/mixdiag/init.lua](../../../../../../extensions/mixdiag/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/mixdiag/init.lua](../../../../../../extensions/mixdiag/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [crates/paw-core/src/measure/mod.rs](../../../../../../crates/paw-core/src/measure/mod.rs) | Invokes supplied callbacks: paw.api.measure, paw.api.measure_cancel, paw.api.measure_poll, paw.api.measure_start | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.index, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.refresh | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.every, paw.flush | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.last_visual, paw.keymap.selection | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.beats_to_seconds, paw.tempo.seconds_to_beats | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/mixdiag/lua/mixdiag/init.lua](../../../../../../extensions/mixdiag/lua/mixdiag/init.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fit, paw.util.merge | teal |
| [extensions/mixdiag/lua/mixdiag/lens.lua](../../../../../../extensions/mixdiag/lua/mixdiag/lens.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/mixdiag/lua/mixdiag/lens.lua](../../../../../../extensions/mixdiag/lua/mixdiag/lens.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.project, paw.address.track | teal |
| [extensions/mixdiag/lua/mixdiag/paint.lua](../../../../../../extensions/mixdiag/lua/mixdiag/paint.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.close, paw.canvas.palette, require("paw.canvas") | teal |
| [extensions/mixdiag/lua/mixdiag/paint.lua](../../../../../../extensions/mixdiag/lua/mixdiag/paint.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.fields | teal |
| [extensions/mixdiag/lua/mixdiag/paint.lua](../../../../../../extensions/mixdiag/lua/mixdiag/paint.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.view | teal |
| [extensions/mixdiag/lua/mixdiag/paint.lua](../../../../../../extensions/mixdiag/lua/mixdiag/paint.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/mixdiag/lua/mixdiag/rules.lua](../../../../../../extensions/mixdiag/lua/mixdiag/rules.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.lane_list | teal |
| [extensions/mixdiag/lua/mixdiag/rules.lua](../../../../../../extensions/mixdiag/lua/mixdiag/rules.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [extensions/mixdiag/lua/mixdiag/rules.lua](../../../../../../extensions/mixdiag/lua/mixdiag/rules.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/mixdiag/lua/mixdiag/rules.lua](../../../../../../extensions/mixdiag/lua/mixdiag/rules.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [extensions/mixdiag/lua/mixdiag/view.lua](../../../../../../extensions/mixdiag/lua/mixdiag/view.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [extensions/mixdiag/lua/mixdiag/view.lua](../../../../../../extensions/mixdiag/lua/mixdiag/view.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callback: paw.canvas.palette | teal |
| [extensions/mixdiag/lua/mixdiag/view.lua](../../../../../../extensions/mixdiag/lua/mixdiag/view.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/mixdiag/lua/mixdiag/view.lua](../../../../../../extensions/mixdiag/lua/mixdiag/view.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [extensions/mixdiag/lua/mixdiag/view.lua](../../../../../../extensions/mixdiag/lua/mixdiag/view.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/mixdiag/lua/mixdiag/view.lua](../../../../../../extensions/mixdiag/lua/mixdiag/view.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend, paw.frontend.bands, paw.frontend.refresh | teal |
| [extensions/mixdiag/lua/mixdiag/view.lua](../../../../../../extensions/mixdiag/lua/mixdiag/view.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.dock, paw.ui.float, paw.ui.focus, paw.ui.hide, paw.ui.hl, paw.ui.notify, paw.ui.open, paw.ui.show, paw.ui.view, paw.ui.views, paw.ui.visible | teal |
| [extensions/mixdiag/lua/mixdiag/view.lua](../../../../../../extensions/mixdiag/lua/mixdiag/view.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [extensions/mixdiag/manifest.lua](../../../../../../extensions/mixdiag/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
