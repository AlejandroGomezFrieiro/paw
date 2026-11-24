---
type: C4 Component
title: Views
status: stable
groma:
  id: views
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/views.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/views.lua](../../../../../../runtime/lua/paw/defaults/views.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/defaults/views.lua](../../../../../../runtime/lua/paw/defaults/views.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.dock, paw.canvas.focus, paw.canvas.open_view, paw.canvas.open_views | teal |
| [runtime/lua/paw/defaults/views.lua](../../../../../../runtime/lua/paw/defaults/views.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.clip | teal |
| [runtime/lua/paw/defaults/views.lua](../../../../../../runtime/lua/paw/defaults/views.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.find, paw.layout.homes, paw.layout.only, paw.layout.split | teal |
| [runtime/lua/paw/defaults/views.lua](../../../../../../runtime/lua/paw/defaults/views.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/defaults/views.lua](../../../../../../runtime/lua/paw/defaults/views.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/defaults/views.lua](../../../../../../runtime/lua/paw/defaults/views.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.float, paw.ui.focus, paw.ui.focus_next, paw.ui.focused, paw.ui.hide, paw.ui.layout, paw.ui.notify, paw.ui.show, paw.ui.toggle, paw.ui.views, paw.ui.visible | teal |
| [runtime/lua/paw/defaults/views.lua](../../../../../../runtime/lua/paw/defaults/views.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
