---
type: C4 Component
title: Edit
status: stable
groma:
  id: edit
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/edit.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_list, paw.api.clip_notes, paw.api.clip_remove, paw.api.clip_set, paw.api.clip_set_controls, paw.api.clip_set_notes | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_list, paw.api.track_remove | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.clip, paw.cursor.index, paw.cursor.on_master, paw.cursor.set_beat, paw.cursor.set_track | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.rows | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [runtime/lua/paw/notes.tl](../../../../../../runtime/lua/paw/notes.tl) | Invokes supplied callbacks: paw.notes.quantize, require("paw.notes") | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.restore_clip, paw.objects.restore_track, paw.objects.track | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | Invokes supplied callback: paw.stretch.carry | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | Invokes supplied callback: paw.takes.piece | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge, paw.util.round, require("paw.util") | teal |
