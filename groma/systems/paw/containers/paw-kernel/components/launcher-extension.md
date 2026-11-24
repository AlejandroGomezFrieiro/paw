---
type: C4 Component
title: Clip launcher extension
status: stable
groma:
  id: launcher-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/launcher/init.lua
    - scanner: teal
      file: extensions/launcher/lua/launcher/init.lua
    - scanner: teal
      file: extensions/launcher/lua/launcher/view.lua
    - scanner: teal
      file: extensions/launcher/manifest.lua
      symbol: launcher
  group: Bundled extensions
  technology: Lua
description: Launches clips from slots and scenes while the song plays.
---

Gives each track slots, a column of clips, and adds the session view of slots and scenes. A scene starts one row of slots. The clips start while the song plays.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_remove, paw.api.clip_set | teal |
| [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.clip, paw.cursor.track_id | teal |
| [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.classic, paw.keymap.getreg, paw.keymap.setreg | teal |
| [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | Invokes supplied callback: paw.learn.trigger | teal |
| [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.input, paw.ui.notify, paw.ui.views | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add, paw.api.clip_controls, paw.api.clip_get, paw.api.clip_list, paw.api.clip_notes, paw.api.clip_remove, paw.api.clip_set, paw.api.clip_to_cues, paw.api.cue, paw.api.cue_list, paw.api.cue_state | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_set | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_set | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callbacks: paw.api.transport_get, paw.api.transport_set | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_checkpoint | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.tempo_bar_of, paw.api.tempo_bar_start | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.arrange | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.off, paw.events.on | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.every | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.restore_clip, paw.objects.time, paw.objects.transport | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callback: paw.tempo.signature_at | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/launcher/lua/launcher/init.lua](../../../../../../extensions/launcher/lua/launcher/init.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.move_track, paw.cursor.set_track, paw.cursor.track_id | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.track_hue | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [runtime/lua/paw/mouse_menus.tl](../../../../../../runtime/lua/paw/mouse_menus.tl) | Invokes supplied callbacks: paw.mouse_menus.clip, require("paw.mouse_menus") | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.grab, paw.mouse.has, paw.mouse.hint, paw.mouse.wheel | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callback: paw.scope.tracks | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.dock, paw.ui.focus, paw.ui.menu, paw.ui.notify, paw.ui.titlebar, paw.ui.view, paw.ui.views, paw.ui.visible | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [extensions/launcher/lua/launcher/view.lua](../../../../../../extensions/launcher/lua/launcher/view.lua) | [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | Invokes supplied callback: paw.vca.is_vca | teal |
| [extensions/launcher/manifest.lua](../../../../../../extensions/launcher/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
