---
type: C4 Component
title: Drums extension
status: stable
groma:
  id: drums-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/drums/init.lua
    - scanner: teal
      file: extensions/drums/lua/drums/beats.lua
    - scanner: teal
      file: extensions/drums/lua/drums/commands.lua
    - scanner: teal
      file: extensions/drums/lua/drums/edit.lua
    - scanner: teal
      file: extensions/drums/lua/drums/grid.lua
    - scanner: teal
      file: extensions/drums/lua/drums/init.lua
    - scanner: teal
      file: extensions/drums/lua/drums/kit.lua
    - scanner: teal
      file: extensions/drums/lua/drums/maps.lua
    - scanner: teal
      file: extensions/drums/manifest.lua
      symbol: drums
  group: Bundled extensions
  technology: Lua
description: Makes drum tracks and shows a grid of the kit pieces by name.
---

Makes a drum track in one step and adds a step grid view whose rows are the pieces of the kit, with their names from the instrument.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/drums/init.lua](../../../../../../extensions/drums/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/drums/lua/drums/beats.lua](../../../../../../extensions/drums/lua/drums/beats.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [extensions/drums/lua/drums/beats.lua](../../../../../../extensions/drums/lua/drums/beats.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.phrase, paw.audition.try | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.index, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.menus | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.classic, paw.keymap.escape_hint, paw.keymap.getreg, paw.keymap.group, paw.keymap.normal, paw.keymap.operator, paw.keymap.setreg, paw.keymap.textobject | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout.back | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callback: paw.track_kinds.define | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.keybar, paw.ui.notify | teal |
| [extensions/drums/lua/drums/commands.lua](../../../../../../extensions/drums/lua/drums/commands.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/drums/lua/drums/edit.lua](../../../../../../extensions/drums/lua/drums/edit.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [extensions/drums/lua/drums/edit.lua](../../../../../../extensions/drums/lua/drums/edit.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/drums/lua/drums/edit.lua](../../../../../../extensions/drums/lua/drums/edit.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/drums/lua/drums/edit.lua](../../../../../../extensions/drums/lua/drums/edit.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.track_colour, paw.draw.track_hue | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.selection | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callback: paw.mouse.grab | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time, paw.objects.transport | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.dock, paw.ui.focus, paw.ui.notify, paw.ui.role, paw.ui.titlebar, paw.ui.view | teal |
| [extensions/drums/lua/drums/grid.lua](../../../../../../extensions/drums/lua/drums/grid.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [extensions/drums/lua/drums/init.lua](../../../../../../extensions/drums/lua/drums/init.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_notes | teal |
| [extensions/drums/lua/drums/init.lua](../../../../../../extensions/drums/lua/drums/init.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, paw.music.pitch | teal |
| [extensions/drums/lua/drums/init.lua](../../../../../../extensions/drums/lua/drums/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.track | teal |
| [extensions/drums/lua/drums/init.lua](../../../../../../extensions/drums/lua/drums/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/drums/lua/drums/init.lua](../../../../../../extensions/drums/lua/drums/init.lua) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callback: paw.track_kinds.add | teal |
| [extensions/drums/lua/drums/init.lua](../../../../../../extensions/drums/lua/drums/init.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
| [extensions/drums/lua/drums/kit.lua](../../../../../../extensions/drums/lua/drums/kit.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_set, paw.api.device_state | teal |
| [extensions/drums/lua/drums/kit.lua](../../../../../../extensions/drums/lua/drums/kit.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [extensions/drums/lua/drums/kit.lua](../../../../../../extensions/drums/lua/drums/kit.lua) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callbacks: paw.bytes.base64, paw.bytes.unbase64 | teal |
| [extensions/drums/lua/drums/kit.lua](../../../../../../extensions/drums/lua/drums/kit.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.device, paw.objects.track | teal |
| [extensions/drums/manifest.lua](../../../../../../extensions/drums/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
