---
type: C4 Component
title: Hardware check extension
status: stable
groma:
  id: doctor-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/doctor/init.lua
    - scanner: teal
      file: extensions/doctor/lua/doctor/checks.lua
    - scanner: teal
      file: extensions/doctor/lua/doctor/gui.lua
      symbol: paint
    - scanner: teal
      file: extensions/doctor/lua/doctor/init.lua
    - scanner: teal
      file: extensions/doctor/lua/doctor/panel.lua
    - scanner: teal
      file: extensions/doctor/lua/doctor/report.lua
    - scanner: teal
      file: extensions/doctor/manifest.lua
      symbol: doctor
    - scanner: teal
      file: extensions/doctor/shell.lua
  group: Bundled extensions
  technology: Lua
description: Checks the audio, MIDI, recording and plugins of the machine.
---

A guided list of checks. For each check, the user starts it and answers, or the check measures by itself. At the end, the extension writes a Markdown report with the facts of the machine.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/doctor/init.lua](../../../../../../extensions/doctor/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.ui_attached, paw.api.ui_redraw | teal |
| [extensions/doctor/init.lua](../../../../../../extensions/doctor/init.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.back, paw.canvas.close, paw.canvas.open | teal |
| [extensions/doctor/init.lua](../../../../../../extensions/doctor/init.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.classic, paw.keymap.escape_hint | teal |
| [extensions/doctor/init.lua](../../../../../../extensions/doctor/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/doctor/init.lua](../../../../../../extensions/doctor/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.dock, paw.ui.float, paw.ui.focus, paw.ui.focused, paw.ui.hide, paw.ui.keybar, paw.ui.notify, paw.ui.open | teal |
| [extensions/doctor/init.lua](../../../../../../extensions/doctor/init.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_types | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.engine_get, paw.api.engine_reset_stats | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: paw.api.limit_async | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callback: paw.api.log_get | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.fs_exists, paw.api.fs_space, paw.api.sound_envelope, paw.api.sound_write, paw.api.which | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | Invokes supplied callbacks: paw.audio.devices, paw.audio.levels | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [runtime/lua/paw/dsp.lua](../../../../../../runtime/lua/paw/dsp.lua) | Invokes supplied callbacks: paw.dsp.db, paw.dsp.gain, require("paw.dsp") | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.off, paw.events.on | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callback: paw.limit.unhurried | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [runtime/lua/paw/media.tl](../../../../../../runtime/lua/paw/media.tl) | Invokes supplied callback: paw.media.list | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.midi, paw.objects.time, paw.objects.transport | teal |
| [extensions/doctor/lua/doctor/checks.lua](../../../../../../extensions/doctor/lua/doctor/checks.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/doctor/lua/doctor/gui.lua](../../../../../../extensions/doctor/lua/doctor/gui.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.button, paw.canvas.hit_list, paw.canvas.palette, require("paw.canvas") | teal |
| [extensions/doctor/lua/doctor/gui.lua](../../../../../../extensions/doctor/lua/doctor/gui.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/doctor/lua/doctor/gui.lua](../../../../../../extensions/doctor/lua/doctor/gui.lua) | [runtime/lua/paw/dsp.lua](../../../../../../runtime/lua/paw/dsp.lua) | Invokes supplied callback: require("paw.dsp") | teal |
| [extensions/doctor/lua/doctor/gui.lua](../../../../../../extensions/doctor/lua/doctor/gui.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/doctor/lua/doctor/init.lua](../../../../../../extensions/doctor/lua/doctor/init.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_backup, paw.api.project_shelve, paw.api.project_unshelve | teal |
| [extensions/doctor/lua/doctor/init.lua](../../../../../../extensions/doctor/lua/doctor/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/doctor/lua/doctor/init.lua](../../../../../../extensions/doctor/lua/doctor/init.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.fs_remove | teal |
| [extensions/doctor/lua/doctor/init.lua](../../../../../../extensions/doctor/lua/doctor/init.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.now, paw.api.real_ms, paw.api.wait | teal |
| [extensions/doctor/lua/doctor/init.lua](../../../../../../extensions/doctor/lua/doctor/init.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/doctor/lua/doctor/init.lua](../../../../../../extensions/doctor/lua/doctor/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.emit | teal |
| [extensions/doctor/lua/doctor/init.lua](../../../../../../extensions/doctor/lua/doctor/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.every, paw.try | teal |
| [extensions/doctor/lua/doctor/init.lua](../../../../../../extensions/doctor/lua/doctor/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.transport | teal |
| [extensions/doctor/lua/doctor/init.lua](../../../../../../extensions/doctor/lua/doctor/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/doctor/lua/doctor/panel.lua](../../../../../../extensions/doctor/lua/doctor/panel.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [extensions/doctor/lua/doctor/panel.lua](../../../../../../extensions/doctor/lua/doctor/panel.lua) | [runtime/lua/paw/dsp.lua](../../../../../../runtime/lua/paw/dsp.lua) | Invokes supplied callback: require("paw.dsp") | teal |
| [extensions/doctor/lua/doctor/panel.lua](../../../../../../extensions/doctor/lua/doctor/panel.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.view | teal |
| [extensions/doctor/lua/doctor/panel.lua](../../../../../../extensions/doctor/lua/doctor/panel.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [extensions/doctor/lua/doctor/report.lua](../../../../../../extensions/doctor/lua/doctor/report.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callback: paw.api.engine_get | teal |
| [extensions/doctor/lua/doctor/report.lua](../../../../../../extensions/doctor/lua/doctor/report.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api.decode, paw.api.encode | teal |
| [extensions/doctor/lua/doctor/report.lua](../../../../../../extensions/doctor/lua/doctor/report.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [extensions/doctor/lua/doctor/report.lua](../../../../../../extensions/doctor/lua/doctor/report.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.real_ms | teal |
| [extensions/doctor/lua/doctor/report.lua](../../../../../../extensions/doctor/lua/doctor/report.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.version | teal |
| [extensions/doctor/manifest.lua](../../../../../../extensions/doctor/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
| [extensions/doctor/shell.lua](../../../../../../extensions/doctor/shell.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [extensions/doctor/shell.lua](../../../../../../extensions/doctor/shell.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.quit | teal |
