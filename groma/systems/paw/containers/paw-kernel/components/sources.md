---
type: C4 Component
title: Sources
status: stable
groma:
  id: sources
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/pick/sources.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list, paw.api.clip_notes, paw.api.clip_remove | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_editor, paw.api.device_get | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw, paw.api.ui_size | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_remove | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.track | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.file, paw.audition.phrase, paw.audition.through, paw.audition.try | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.exec, paw.commands.list, paw.commands.run, paw.commands.used, paw.commands.uses | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track, paw.cursor.track_id | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.format_value | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callbacks: paw.fx.add, paw.fx.added, paw.fx.device_line, paw.fx.device_list, paw.fx.place, paw.fx.preferred, paw.fx.rank, paw.fx.toggle_favourite | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | Invokes supplied callbacks: paw.help.excerpt_for_map, paw.help.for_command, paw.help.for_map | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.open | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.all, paw.keymap.goto_mark, paw.keymap.human, paw.keymap.list, paw.keymap.marks, paw.keymap.mode, paw.keymap.normal, paw.keymap.play, paw.keymap.push_jump, paw.keymap.registers | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | Invokes supplied callback: paw.midifile.is_midi_file | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.project, paw.objects.time | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.list, paw.options.opt, paw.options.read, require("paw.options") | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | Invokes supplied callback: paw.panes.cells | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/pick/preview.tl](../../../../../../runtime/lua/paw/pick/preview.tl) | Invokes supplied callbacks: paw.pick.preview.clip, require("paw.pick.preview") | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | Invokes supplied callbacks: paw.pick.project.Sources, paw.pick.project.objects, require("paw.pick.project") | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callback: paw.scope.tracks | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.focused, paw.ui.input, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
| [runtime/lua/paw/pick/sources.tl](../../../../../../runtime/lua/paw/pick/sources.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fit, require("paw.util") | teal |
