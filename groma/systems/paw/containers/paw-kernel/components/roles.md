---
type: C4 Component
title: Roles
status: stable
groma:
  id: roles
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/roles.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [crates/paw-core/src/scene.rs](../../../../../../crates/paw-core/src/scene.rs) | Invokes supplied callbacks: paw.api.scene_close, paw.api.scene_hit, paw.api.scene_open | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/buf.tl](../../../../../../runtime/lua/paw/buf.tl) | Invokes supplied callbacks: paw.buf.hit, paw.buf.mark, require("paw.buf") | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callback: paw.canvas.focus | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.feed | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callback: paw.limit.named | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.gesture, paw.mouse.hint, paw.mouse.mark_double, paw.mouse.to_view | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | Invokes supplied callback: paw.panes.focus | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, paw.registry.registry, require("paw.registry") | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.keep | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.live, paw.ui.live_drawing, paw.ui.live_stamp, paw.ui.live_value, paw.ui.scene_drawing | teal |
| [runtime/lua/paw/roles.tl](../../../../../../runtime/lua/paw/roles.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
