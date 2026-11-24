---
type: C4 Component
title: Ex
status: stable
groma:
  id: ex
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/ex.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list, paw.api.clip_notes, paw.api.clip_remove, paw.api.clip_set, paw.api.notes_set | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_remove, paw.api.track_set | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.find_note, paw.address.note, paw.address.parse, paw.address.track | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/attr.tl](../../../../../../runtime/lua/paw/attr.tl) | Invokes supplied callback: paw.attr.m2 | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.about, paw.commands.alias, paw.commands.define, paw.commands.exec, paw.commands.get, paw.commands.main, paw.commands.params, paw.commands.parse, paw.commands.run, paw.commands.unknown, require("paw.commands") | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track_id | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.arrange | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.rows | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, require("paw.music") | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/notes.tl](../../../../../../runtime/lua/paw/notes.tl) | Invokes supplied callbacks: paw.notes.snap, require("paw.notes") | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.restore_clip, paw.objects.restore_track, paw.objects.time, paw.objects.track | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callbacks: paw.qf.go, paw.qf.set | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/roll_clips.tl](../../../../../../runtime/lua/paw/roll_clips.tl) | Invokes supplied callback: paw.roll_clips.ids | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope.bar_offset, paw.scope.nest, paw.scope.span, paw.scope.tracks | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui, paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge, require("paw.util") | teal |
