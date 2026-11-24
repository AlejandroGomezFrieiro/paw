---
type: C4 Component
title: Markers
status: stable
groma:
  id: markers
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/markers.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_set | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_attached | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.Context, paw.commands.Result, paw.commands.define, paw.commands.run, require("paw.commands") | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_beat | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.selection | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.time, paw.objects.transport | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | Invokes supplied callback: paw.render | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | Invokes supplied callbacks: paw.ruler.add_lane, paw.ruler.loop_text | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.notify | teal |
| [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.fit, require("paw.util") | teal |
