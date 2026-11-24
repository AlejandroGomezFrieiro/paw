---
type: C4 Component
title: Stems
status: stable
groma:
  id: stems
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/stems.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.is_group, paw.groups.members, paw.groups.of | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | Invokes supplied callbacks: paw.render, require("paw.render") | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope.contains, paw.scope.find, paw.scope.group, paw.scope.tracks | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.fields | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.notify, paw.ui.open, paw.ui.view | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit, paw.util.merge | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | Invokes supplied callback: paw.vca.is_vca | teal |
| [runtime/lua/paw/stems.lua](../../../../../../runtime/lua/paw/stems.lua) | [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | Invokes supplied callback: paw.views.files.path | teal |
