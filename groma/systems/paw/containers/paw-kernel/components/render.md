---
type: C4 Component
title: Render
status: stable
groma:
  id: render
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/render.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callbacks: paw.api.render, paw.api.render_cancel, paw.api.render_check, paw.api.render_start, paw.api.render_status | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_set | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.define, require("paw.commands") | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.render_cancelled, paw.events.kernel.render_done, paw.events.kernel.render_failed, paw.events.kernel.render_progress, require("paw.events.kernel") | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callback: paw.groups.is_group | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.selection | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.tracks | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.poke | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.expand_path, paw.util.merge, require("paw.util") | teal |
| [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | Invokes supplied callback: paw.views.files | teal |
