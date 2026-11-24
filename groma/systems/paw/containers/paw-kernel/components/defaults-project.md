---
type: C4 Component
title: Project
status: stable
groma:
  id: defaults-project
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/project.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.engine_get, paw.api.engine_restart, paw.api.engine_set_sleep, paw.api.engine_set_threads | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.chain_write, paw.api.project_files, paw.api.project_get, paw.api.project_mark_saved, paw.api.project_save_files | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.quit, paw.api.real_ms, paw.api.reload, paw.api.sleep | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_list, paw.api.track_set | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.redo, paw.api.undo, paw.api.undo_current, paw.api.undo_label, paw.api.undo_reset, paw.api.undo_tree | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/audio.lua](../../../../../../runtime/lua/paw/audio.lua) | Invokes supplied callbacks: paw.audio.choose_engine, paw.audio.devices, paw.audio.engine_choices, paw.audio.timing | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.alias, paw.commands.complete, paw.commands.exec, paw.commands.list, paw.commands.run, paw.commands.used | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callback: require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | Invokes supplied callback: paw.ex.preview | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callbacks: paw.ext.bundled, paw.ext.list, paw.ext.load_bundled, paw.ext.loaded, paw.ext.provides, paw.ext.unload | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/formats.tl](../../../../../../runtime/lua/paw/formats.tl) | Invokes supplied callbacks: paw.formats.export, paw.formats.for_path | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.save_as | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callback: paw.fx.interactive | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | Invokes supplied callback: paw.help.roots | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.bounce, paw.chain_document, paw.defer, paw.is_audio_file, paw.is_chain_file, paw.open | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.selection, paw.keymap.set_mode | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/lanes.tl](../../../../../../runtime/lua/paw/lanes.tl) | Invokes supplied callbacks: paw.lanes.mode_text, paw.lanes.modes | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.current, paw.layout.resolve, paw.layout.show_in | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callbacks: paw.limit.extend, paw.limit.untrusted | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | Invokes supplied callbacks: paw.midifile.document, paw.midifile.is_clip_file, paw.midifile.write_clip | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.project, paw.objects.transport | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.messages, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.inspect | teal |
| [runtime/lua/paw/defaults/project.lua](../../../../../../runtime/lua/paw/defaults/project.lua) | [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | Invokes supplied callbacks: paw.views.files.is_dir, paw.views.files.open, paw.views.files.path, paw.views.files.project_path | teal |
