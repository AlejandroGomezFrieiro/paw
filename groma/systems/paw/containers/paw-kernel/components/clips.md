---
type: C4 Component
title: Clips
status: stable
groma:
  id: clips
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/clips.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_link, paw.api.clip_set, paw.api.clip_source_length, paw.api.clip_unlink, paw.api.media_adopt | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_new, paw.api.project_set, paw.api.track_chain_file, paw.api.track_import_folder | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_reset | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.index, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callbacks: paw.defaults.common.overrides_text, require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.arrange | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/formats.tl](../../../../../../runtime/lua/paw/formats.tl) | Invokes supplied callbacks: paw.formats.export, paw.formats.extensions, paw.formats.for_path, paw.formats.import, paw.formats.register, paw.formats.split_args | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend.act, paw.frontend.openers | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.chain_document, paw.import_audio, paw.is_audio_file, paw.is_chain_file, paw.open, paw.open_chain | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.selection, paw.keymap.set_mode | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/loading.lua](../../../../../../runtime/lua/paw/loading.lua) | Invokes supplied callback: paw.loading.open | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/midifile.tl](../../../../../../runtime/lua/paw/midifile.tl) | Invokes supplied callbacks: paw.midifile.export, paw.midifile.extensions, paw.midifile.import, paw.midifile.import_clip, paw.midifile.is_clip_file, paw.midifile.is_midi_file, paw.midifile.lost_text, paw.midifile.open, paw.midifile.open_clip | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.clip, paw.objects.project, paw.objects.time, paw.objects.track | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.full, paw.options.list, paw.options.opt, paw.options.read, paw.options.show | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callbacks: paw.pick, paw.pick.file | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | Invokes supplied callback: require("paw.render") | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope.describe, paw.scope.enter, paw.scope.of_clip | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | Invokes supplied callbacks: paw.stretch.carry, paw.stretch.fit, paw.stretch.follow, paw.stretch.loop, paw.stretch.pitch, paw.stretch.reset, paw.stretch.set, paw.stretch.to, paw.stretch.warp_add, paw.stretch.warp_move, paw.stretch.warp_near, paw.stretch.warp_remove, paw.stretch.warp_snap | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | Invokes supplied callback: paw.takes.piece | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.notify, paw.ui.show, paw.ui.views | teal |
| [runtime/lua/paw/defaults/clips.lua](../../../../../../runtime/lua/paw/defaults/clips.lua) | [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | Invokes supplied callbacks: paw.views.files.is_dir, paw.views.files.open, paw.views.files.path | teal |
