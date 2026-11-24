---
type: C4 Component
title: Virtual inputs extension
status: stable
groma:
  id: vinput-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/vinput/init.lua
    - scanner: teal
      file: extensions/vinput/lua/vinput/commands.lua
    - scanner: teal
      file: extensions/vinput/lua/vinput/gdi2m.lua
    - scanner: teal
      file: extensions/vinput/lua/vinput/gui.lua
    - scanner: teal
      file: extensions/vinput/lua/vinput/init.lua
    - scanner: teal
      file: extensions/vinput/lua/vinput/panel.lua
    - scanner: teal
      file: extensions/vinput/lua/vinput/run.lua
    - scanner: teal
      file: extensions/vinput/manifest.lua
      symbol: vinput
  group: Bundled extensions
  technology: Lua
description: Changes a guitar signal into MIDI as an input that a track can take.
---

A virtual input is a chain that changes another kind of signal into a track input. The only kind now hears a guitar as MIDI through gdi2m.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/vinput/init.lua](../../../../../../extensions/vinput/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/vinput/lua/vinput/commands.lua](../../../../../../extensions/vinput/lua/vinput/commands.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/vinput/lua/vinput/commands.lua](../../../../../../extensions/vinput/lua/vinput/commands.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callback: paw.canvas.open | teal |
| [extensions/vinput/lua/vinput/commands.lua](../../../../../../extensions/vinput/lua/vinput/commands.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.menus | teal |
| [extensions/vinput/lua/vinput/commands.lua](../../../../../../extensions/vinput/lua/vinput/commands.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.classic, paw.keymap.escape_hint | teal |
| [extensions/vinput/lua/vinput/commands.lua](../../../../../../extensions/vinput/lua/vinput/commands.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout.back | teal |
| [extensions/vinput/lua/vinput/commands.lua](../../../../../../extensions/vinput/lua/vinput/commands.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/vinput/lua/vinput/commands.lua](../../../../../../extensions/vinput/lua/vinput/commands.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.focused, paw.ui.input, paw.ui.keybar, paw.ui.notify | teal |
| [extensions/vinput/lua/vinput/commands.lua](../../../../../../extensions/vinput/lua/vinput/commands.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/vinput/lua/vinput/gdi2m.lua](../../../../../../extensions/vinput/lua/vinput/gdi2m.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.pitch | teal |
| [extensions/vinput/lua/vinput/gui.lua](../../../../../../extensions/vinput/lua/vinput/gui.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.button, paw.canvas.hit_list, paw.canvas.palette, require("paw.canvas") | teal |
| [extensions/vinput/lua/vinput/gui.lua](../../../../../../extensions/vinput/lua/vinput/gui.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.mix | teal |
| [extensions/vinput/lua/vinput/gui.lua](../../../../../../extensions/vinput/lua/vinput/gui.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/vinput/lua/vinput/gui.lua](../../../../../../extensions/vinput/lua/vinput/gui.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.round | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api.decode, paw.api.encode | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_set | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.index, paw.cursor.set_track | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.on | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.midi | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/vinput/lua/vinput/init.lua](../../../../../../extensions/vinput/lua/vinput/init.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge, paw.util.round | teal |
| [extensions/vinput/lua/vinput/panel.lua](../../../../../../extensions/vinput/lua/vinput/panel.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [extensions/vinput/lua/vinput/panel.lua](../../../../../../extensions/vinput/lua/vinput/panel.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.slider | teal |
| [extensions/vinput/lua/vinput/panel.lua](../../../../../../extensions/vinput/lua/vinput/panel.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.dock, paw.ui.titlebar, paw.ui.view | teal |
| [extensions/vinput/lua/vinput/panel.lua](../../../../../../extensions/vinput/lua/vinput/panel.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callback: paw.api.engine_get | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: paw.api.vinput_procs | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callbacks: paw.api.proc_kill, paw.api.proc_spawn, paw.api.proc_status, paw.api.proc_stop | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.now, paw.api.real_ms, paw.api.sleep | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.every | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.midi | teal |
| [extensions/vinput/lua/vinput/run.lua](../../../../../../extensions/vinput/lua/vinput/run.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.visible | teal |
| [extensions/vinput/manifest.lua](../../../../../../extensions/vinput/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
