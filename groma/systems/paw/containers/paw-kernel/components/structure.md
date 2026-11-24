---
type: C4 Component
title: Structure
status: stable
groma:
  id: structure
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/structure.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.Context, paw.commands.define, require("paw.commands") | teal |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.track, paw.cursor.track_id | teal |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.fold, paw.groups.folded, paw.groups.is_group, paw.groups.members, paw.groups.of, paw.groups.rows | teal |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.set, paw.keymap.textobject | teal |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [runtime/lua/paw/query.tl](../../../../../../runtime/lua/paw/query.tl) | Invokes supplied callbacks: paw.query.KINDS, paw.query.select | teal |
| [runtime/lua/paw/structure.tl](../../../../../../runtime/lua/paw/structure.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.views | teal |
