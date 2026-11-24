---
type: C4 Component
title: Project
status: stable
groma:
  id: pick-project
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/pick/project.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_list, paw.api.clip_notes, paw.api.media_list | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_current, paw.api.undo_diff, paw.api.undo_goto, paw.api.undo_label, paw.api.undo_tree | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.marker, paw.address.parse, require("paw.address") | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.phrase, paw.audition.through | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_beat, paw.cursor.track | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callbacks: paw.ext.bundled, paw.ext.bundled_dir, paw.ext.list, paw.ext.load_bundled | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/fx.lua](../../../../../../runtime/lua/paw/fx.lua) | Invokes supplied callback: paw.fx.pick | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | Invokes supplied callback: paw.grep.reader | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/help.tl](../../../../../../runtime/lua/paw/help.tl) | Invokes supplied callbacks: paw.help.index, paw.help.jump, paw.help.lookup, paw.help.open, paw.help.show | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.human, paw.keymap.push_jump | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.buf_create, paw.layout.current, paw.layout.show_in, paw.layout.split, paw.layout.tab_new | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers.depth, paw.markers.label, paw.markers.list, paw.markers.pathname, paw.markers.remove, paw.markers.walk | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/pick/preview.tl](../../../../../../runtime/lua/paw/pick/preview.tl) | Invokes supplied callbacks: paw.pick.preview.clip, paw.pick.preview.roll, paw.pick.preview.width, require("paw.pick.preview") | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callbacks: paw.qf.current, paw.qf.go, paw.qf.jump, paw.qf.where | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | Invokes supplied callbacks: paw.query.articulations, paw.query.run | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.input, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
| [runtime/lua/paw/pick/project.tl](../../../../../../runtime/lua/paw/pick/project.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fit, require("paw.util") | teal |
