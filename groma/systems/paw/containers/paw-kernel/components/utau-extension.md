---
type: C4 Component
title: Singing extension
status: stable
groma:
  id: utau-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/utau/devices/utau.lua
    - scanner: teal
      file: extensions/utau/images/make/scene.lua
    - scanner: teal
      file: extensions/utau/init.lua
    - scanner: teal
      file: extensions/utau/lua/utau/audition.lua
    - scanner: teal
      file: extensions/utau/lua/utau/batch.lua
    - scanner: teal
      file: extensions/utau/lua/utau/commands.lua
    - scanner: teal
      file: extensions/utau/lua/utau/editor.lua
    - scanner: teal
      file: extensions/utau/lua/utau/editor_keys.lua
    - scanner: teal
      file: extensions/utau/lua/utau/engine.lua
    - scanner: teal
      file: extensions/utau/lua/utau/export.lua
    - scanner: teal
      file: extensions/utau/lua/utau/follow.lua
    - scanner: teal
      file: extensions/utau/lua/utau/freeze.lua
    - scanner: teal
      file: extensions/utau/lua/utau/gui.lua
    - scanner: teal
      file: extensions/utau/lua/utau/gui_curves.lua
    - scanner: teal
      file: extensions/utau/lua/utau/gui_inspector.lua
    - scanner: teal
      file: extensions/utau/lua/utau/gui_pitch.lua
    - scanner: teal
      file: extensions/utau/lua/utau/harmony.lua
    - scanner: teal
      file: extensions/utau/lua/utau/import.lua
    - scanner: teal
      file: extensions/utau/lua/utau/init.lua
    - scanner: teal
      file: extensions/utau/lua/utau/install.lua
    - scanner: teal
      file: extensions/utau/lua/utau/json.lua
    - scanner: teal
      file: extensions/utau/lua/utau/kana.lua
    - scanner: teal
      file: extensions/utau/lua/utau/lyrics.lua
    - scanner: teal
      file: extensions/utau/lua/utau/msgpack.lua
    - scanner: teal
      file: extensions/utau/lua/utau/notes.lua
    - scanner: teal
      file: extensions/utau/lua/utau/payload.lua
    - scanner: teal
      file: extensions/utau/lua/utau/proto.lua
    - scanner: teal
      file: extensions/utau/lua/utau/renderer.lua
    - scanner: teal
      file: extensions/utau/lua/utau/shapes.lua
    - scanner: teal
      file: extensions/utau/lua/utau/singer_presets.lua
    - scanner: teal
      file: extensions/utau/lua/utau/step.tl
    - scanner: teal
      file: extensions/utau/lua/utau/strips.lua
    - scanner: teal
      file: extensions/utau/lua/utau/voices.lua
    - scanner: teal
      file: extensions/utau/manifest.lua
      symbol: utau
  group: Bundled extensions
  technology: Lua
description: Adds vocal tracks that OpenUtau engines sing, and a vocal editor.
---

Adds vocal tracks, a vocal editor and the device that plays the singing. It starts the paw-utau-engine container and talks to it through a Unix socket. The engine renders the phrases with OpenUtau engines and sends the audio back.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/utau/devices/utau.lua](../../../../../../extensions/utau/devices/utau.lua) | [runtime/lua/paw/dsp.lua](../../../../../../runtime/lua/paw/dsp.lua) | Invokes supplied callbacks: paw.dsp.buffer, paw.dsp.device, paw.dsp.map, require("paw.dsp") | teal |
| [extensions/utau/images/make/scene.lua](../../../../../../extensions/utau/images/make/scene.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_notes | teal |
| [extensions/utau/images/make/scene.lua](../../../../../../extensions/utau/images/make/scene.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.set_beat, paw.cursor.set_track | teal |
| [extensions/utau/images/make/scene.lua](../../../../../../extensions/utau/images/make/scene.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.load | teal |
| [extensions/utau/images/make/scene.lua](../../../../../../extensions/utau/images/make/scene.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.flush | teal |
| [extensions/utau/images/make/scene.lua](../../../../../../extensions/utau/images/make/scene.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.tracks | teal |
| [extensions/utau/images/make/scene.lua](../../../../../../extensions/utau/images/make/scene.lua) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callback: paw.track_kinds.add | teal |
| [extensions/utau/init.lua](../../../../../../extensions/utau/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/utau/init.lua](../../../../../../extensions/utau/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/utau/init.lua](../../../../../../extensions/utau/init.lua) | [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | Invokes supplied callback: paw.health.register | teal |
| [extensions/utau/init.lua](../../../../../../extensions/utau/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.every | teal |
| [extensions/utau/init.lua](../../../../../../extensions/utau/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/utau/init.lua](../../../../../../extensions/utau/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/utau/lua/utau/audition.lua](../../../../../../extensions/utau/lua/utau/audition.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes | teal |
| [extensions/utau/lua/utau/audition.lua](../../../../../../extensions/utau/lua/utau/audition.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/utau/lua/utau/audition.lua](../../../../../../extensions/utau/lua/utau/audition.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/utau/lua/utau/audition.lua](../../../../../../extensions/utau/lua/utau/audition.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/utau/lua/utau/batch.lua](../../../../../../extensions/utau/lua/utau/batch.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes, paw.api.clip_set_notes | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.set_track, paw.cursor.track, paw.cursor.track_id | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | Invokes supplied callback: paw.insert.add | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.classic, paw.keymap.escape_hint, paw.keymap.getreg, paw.keymap.group, paw.keymap.operator, paw.keymap.setreg, paw.keymap.textobject | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout.back | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callbacks: paw.pick, paw.pick.sources | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callbacks: paw.track_kinds.define, paw.track_kinds.set | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.hide, paw.ui.notify, paw.ui.toggle | teal |
| [extensions/utau/lua/utau/commands.lua](../../../../../../extensions/utau/lua/utau/commands.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/utau/lua/utau/editor_keys.lua](../../../../../../extensions/utau/lua/utau/editor_keys.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/utau/lua/utau/editor_keys.lua](../../../../../../extensions/utau/lua/utau/editor_keys.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callback: paw.canvas.shown | teal |
| [extensions/utau/lua/utau/editor_keys.lua](../../../../../../extensions/utau/lua/utau/editor_keys.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [extensions/utau/lua/utau/editor_keys.lua](../../../../../../extensions/utau/lua/utau/editor_keys.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.classic, paw.keymap.getreg, paw.keymap.setreg, paw.keymap.textobject, paw.keymap.visual_start | teal |
| [extensions/utau/lua/utau/editor_keys.lua](../../../../../../extensions/utau/lua/utau/editor_keys.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.clip | teal |
| [extensions/utau/lua/utau/editor_keys.lua](../../../../../../extensions/utau/lua/utau/editor_keys.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/utau/lua/utau/editor_keys.lua](../../../../../../extensions/utau/lua/utau/editor_keys.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.lane_points | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add_notes, paw.api.clip_get, paw.api.clip_set_notes | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_cursor, paw.api.ui_redraw | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.clip | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.beats, paw.draw.curve, paw.draw.g, paw.draw.piano_key, paw.draw.track_hue | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.selection, paw.keymap.set_mode | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.is_black, paw.music.name | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callbacks: paw.theme.palette, require("paw.theme") | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.dock, paw.ui.focus, paw.ui.input, paw.ui.keybar, paw.ui.notify, paw.ui.open, paw.ui.theme, paw.ui.titlebar, paw.ui.view | teal |
| [extensions/utau/lua/utau/editor.lua](../../../../../../extensions/utau/lua/utau/editor.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit, paw.util.merge | teal |
| [extensions/utau/lua/utau/engine.lua](../../../../../../extensions/utau/lua/utau/engine.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: paw.api.utau_link | teal |
| [extensions/utau/lua/utau/engine.lua](../../../../../../extensions/utau/lua/utau/engine.lua) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callbacks: paw.api.proc_kill, paw.api.proc_spawn, paw.api.proc_status, paw.api.sock_accept, paw.api.sock_close, paw.api.sock_listen, paw.api.sock_read, paw.api.sock_write | teal |
| [extensions/utau/lua/utau/engine.lua](../../../../../../extensions/utau/lua/utau/engine.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [extensions/utau/lua/utau/engine.lua](../../../../../../extensions/utau/lua/utau/engine.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.now, paw.api.real_ms, paw.api.sleep | teal |
| [extensions/utau/lua/utau/engine.lua](../../../../../../extensions/utau/lua/utau/engine.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/utau/lua/utau/engine.lua](../../../../../../extensions/utau/lua/utau/engine.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.loaded | teal |
| [extensions/utau/lua/utau/engine.lua](../../../../../../extensions/utau/lua/utau/engine.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.try | teal |
| [extensions/utau/lua/utau/engine.lua](../../../../../../extensions/utau/lua/utau/engine.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/utau/lua/utau/engine.lua](../../../../../../extensions/utau/lua/utau/engine.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/utau/lua/utau/export.lua](../../../../../../extensions/utau/lua/utau/export.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [extensions/utau/lua/utau/export.lua](../../../../../../extensions/utau/lua/utau/export.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.base64_encode | teal |
| [extensions/utau/lua/utau/export.lua](../../../../../../extensions/utau/lua/utau/export.lua) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callback: paw.api.proc_spawn | teal |
| [extensions/utau/lua/utau/export.lua](../../../../../../extensions/utau/lua/utau/export.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/utau/lua/utau/export.lua](../../../../../../extensions/utau/lua/utau/export.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [extensions/utau/lua/utau/export.lua](../../../../../../extensions/utau/lua/utau/export.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/utau/lua/utau/export.lua](../../../../../../extensions/utau/lua/utau/export.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/utau/lua/utau/follow.lua](../../../../../../extensions/utau/lua/utau/follow.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_get, paw.api.lane_list, paw.api.lane_points, paw.api.lane_set_points | teal |
| [extensions/utau/lua/utau/follow.lua](../../../../../../extensions/utau/lua/utau/follow.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list, paw.api.clip_set | teal |
| [extensions/utau/lua/utau/follow.lua](../../../../../../extensions/utau/lua/utau/follow.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/utau/lua/utau/follow.lua](../../../../../../extensions/utau/lua/utau/follow.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/utau/lua/utau/follow.lua](../../../../../../extensions/utau/lua/utau/follow.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/utau/lua/utau/freeze.lua](../../../../../../extensions/utau/lua/utau/freeze.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_remove | teal |
| [extensions/utau/lua/utau/freeze.lua](../../../../../../extensions/utau/lua/utau/freeze.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.bounce, paw.flush | teal |
| [extensions/utau/lua/utau/freeze.lua](../../../../../../extensions/utau/lua/utau/freeze.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.track | teal |
| [extensions/utau/lua/utau/freeze.lua](../../../../../../extensions/utau/lua/utau/freeze.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/utau/lua/utau/gui_curves.lua](../../../../../../extensions/utau/lua/utau/gui_curves.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points | teal |
| [extensions/utau/lua/utau/gui_curves.lua](../../../../../../extensions/utau/lua/utau/gui_curves.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/utau/lua/utau/gui_curves.lua](../../../../../../extensions/utau/lua/utau/gui_curves.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/utau/lua/utau/gui_curves.lua](../../../../../../extensions/utau/lua/utau/gui_curves.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.palette, require("paw.canvas") | teal |
| [extensions/utau/lua/utau/gui_curves.lua](../../../../../../extensions/utau/lua/utau/gui_curves.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/utau/lua/utau/gui_curves.lua](../../../../../../extensions/utau/lua/utau/gui_curves.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/utau/lua/utau/gui_curves.lua](../../../../../../extensions/utau/lua/utau/gui_curves.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/utau/lua/utau/gui_inspector.lua](../../../../../../extensions/utau/lua/utau/gui_inspector.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.palette, require("paw.canvas") | teal |
| [extensions/utau/lua/utau/gui_inspector.lua](../../../../../../extensions/utau/lua/utau/gui_inspector.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [extensions/utau/lua/utau/gui_inspector.lua](../../../../../../extensions/utau/lua/utau/gui_inspector.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/utau/lua/utau/gui_inspector.lua](../../../../../../extensions/utau/lua/utau/gui_inspector.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/utau/lua/utau/gui_inspector.lua](../../../../../../extensions/utau/lua/utau/gui_inspector.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/utau/lua/utau/gui_pitch.lua](../../../../../../extensions/utau/lua/utau/gui_pitch.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/utau/lua/utau/gui_pitch.lua](../../../../../../extensions/utau/lua/utau/gui_pitch.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.palette, require("paw.canvas") | teal |
| [extensions/utau/lua/utau/gui_pitch.lua](../../../../../../extensions/utau/lua/utau/gui_pitch.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/utau/lua/utau/gui_pitch.lua](../../../../../../extensions/utau/lua/utau/gui_pitch.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.lane_points | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.button, paw.canvas.close, paw.canvas.hit_list, paw.canvas.open, paw.canvas.palette, require("paw.canvas") | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.track_colour | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.menus | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time, paw.objects.transport | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.at, paw.tempo.seconds_to_beats | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.hide | teal |
| [extensions/utau/lua/utau/gui.lua](../../../../../../extensions/utau/lua/utau/gui.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
| [extensions/utau/lua/utau/harmony.lua](../../../../../../extensions/utau/lua/utau/harmony.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_list, paw.api.clip_notes | teal |
| [extensions/utau/lua/utau/harmony.lua](../../../../../../extensions/utau/lua/utau/harmony.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [extensions/utau/lua/utau/harmony.lua](../../../../../../extensions/utau/lua/utau/harmony.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.key_name, paw.harmony.project_key | teal |
| [extensions/utau/lua/utau/harmony.lua](../../../../../../extensions/utau/lua/utau/harmony.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music, paw.music.scales | teal |
| [extensions/utau/lua/utau/harmony.lua](../../../../../../extensions/utau/lua/utau/harmony.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.restore_track, paw.objects.track | teal |
| [extensions/utau/lua/utau/import.lua](../../../../../../extensions/utau/lua/utau/import.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.lane_add | teal |
| [extensions/utau/lua/utau/import.lua](../../../../../../extensions/utau/lua/utau/import.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_add | teal |
| [extensions/utau/lua/utau/import.lua](../../../../../../extensions/utau/lua/utau/import.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_add | teal |
| [extensions/utau/lua/utau/import.lua](../../../../../../extensions/utau/lua/utau/import.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_add, paw.api.track_set | teal |
| [extensions/utau/lua/utau/import.lua](../../../../../../extensions/utau/lua/utau/import.lua) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callback: paw.api.signature_set | teal |
| [extensions/utau/lua/utau/import.lua](../../../../../../extensions/utau/lua/utau/import.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.bar_start, paw.tempo.set_points | teal |
| [extensions/utau/lua/utau/import.lua](../../../../../../extensions/utau/lua/utau/import.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_list, paw.api.clip_notes | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set, paw.api.device_set_param | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.now, paw.api.real_ms, paw.api.sleep | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.beat | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.beats_to_seconds, paw.tempo.points, paw.tempo.seconds_between, paw.tempo.signatures | teal |
| [extensions/utau/lua/utau/init.lua](../../../../../../extensions/utau/lua/utau/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/utau/lua/utau/install.lua](../../../../../../extensions/utau/lua/utau/install.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [extensions/utau/lua/utau/install.lua](../../../../../../extensions/utau/lua/utau/install.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callbacks: paw.api.fs_copy, paw.api.fs_mkdir, paw.api.fs_stat | teal |
| [extensions/utau/lua/utau/json.lua](../../../../../../extensions/utau/lua/utau/json.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_array, paw.api.json_decode, paw.api.json_encode | teal |
| [extensions/utau/lua/utau/notes.lua](../../../../../../extensions/utau/lua/utau/notes.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_add, paw.api.lane_list, paw.api.lane_points, paw.api.lane_set_points | teal |
| [extensions/utau/lua/utau/notes.lua](../../../../../../extensions/utau/lua/utau/notes.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_notes, paw.api.clip_set_notes | teal |
| [extensions/utau/lua/utau/notes.lua](../../../../../../extensions/utau/lua/utau/notes.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/utau/lua/utau/renderer.lua](../../../../../../extensions/utau/lua/utau/renderer.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.lane_remove | teal |
| [extensions/utau/lua/utau/renderer.lua](../../../../../../extensions/utau/lua/utau/renderer.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_notes | teal |
| [extensions/utau/lua/utau/renderer.lua](../../../../../../extensions/utau/lua/utau/renderer.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_set_param | teal |
| [extensions/utau/lua/utau/renderer.lua](../../../../../../extensions/utau/lua/utau/renderer.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/utau/lua/utau/renderer.lua](../../../../../../extensions/utau/lua/utau/renderer.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/utau/lua/utau/renderer.lua](../../../../../../extensions/utau/lua/utau/renderer.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/utau/lua/utau/singer_presets.lua](../../../../../../extensions/utau/lua/utau/singer_presets.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set_param | teal |
| [extensions/utau/lua/utau/singer_presets.lua](../../../../../../extensions/utau/lua/utau/singer_presets.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [extensions/utau/lua/utau/singer_presets.lua](../../../../../../extensions/utau/lua/utau/singer_presets.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/utau/lua/utau/step.tl](../../../../../../extensions/utau/lua/utau/step.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add_notes, paw.api.clip_set_notes | teal |
| [extensions/utau/lua/utau/step.tl](../../../../../../extensions/utau/lua/utau/step.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/utau/lua/utau/step.tl](../../../../../../extensions/utau/lua/utau/step.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_current, paw.api.undo_join | teal |
| [extensions/utau/lua/utau/step.tl](../../../../../../extensions/utau/lua/utau/step.tl) | [runtime/lua/paw/contracts.tl](../../../../../../runtime/lua/paw/contracts.tl) | Invokes supplied callback: paw.contracts.StepAction | teal |
| [extensions/utau/lua/utau/step.tl](../../../../../../extensions/utau/lua/utau/step.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/utau/lua/utau/step.tl](../../../../../../extensions/utau/lua/utau/step.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.mode_changed, paw.keymap.set_mode | teal |
| [extensions/utau/lua/utau/step.tl](../../../../../../extensions/utau/lua/utau/step.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/utau/lua/utau/step.tl](../../../../../../extensions/utau/lua/utau/step.tl) | [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | Invokes supplied callbacks: paw.step.refresh, paw.step.target | teal |
| [extensions/utau/lua/utau/step.tl](../../../../../../extensions/utau/lua/utau/step.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui, paw.ui.notify | teal |
| [extensions/utau/lua/utau/strips.lua](../../../../../../extensions/utau/lua/utau/strips.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/utau/lua/utau/strips.lua](../../../../../../extensions/utau/lua/utau/strips.lua) | [runtime/lua/paw/plot.tl](../../../../../../runtime/lua/paw/plot.tl) | Invokes supplied callbacks: paw.plot.alpha, paw.plot.curve, paw.plot.lines | teal |
| [extensions/utau/lua/utau/strips.lua](../../../../../../extensions/utau/lua/utau/strips.lua) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callback: require("paw.theme") | teal |
| [extensions/utau/lua/utau/voices.lua](../../../../../../extensions/utau/lua/utau/voices.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_alias, paw.api.device_call, paw.api.device_get, paw.api.device_post | teal |
| [extensions/utau/lua/utau/voices.lua](../../../../../../extensions/utau/lua/utau/voices.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.fs_remove, paw.api.read_dir | teal |
| [extensions/utau/lua/utau/voices.lua](../../../../../../extensions/utau/lua/utau/voices.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/utau/lua/utau/voices.lua](../../../../../../extensions/utau/lua/utau/voices.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/utau/manifest.lua](../../../../../../extensions/utau/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
