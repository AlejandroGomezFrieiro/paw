---
type: C4 Component
title: Qflist
status: stable
groma:
  id: qflist
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/qflist.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/qflist.lua](../../../../../../runtime/lua/paw/views/qflist.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/qflist.lua](../../../../../../runtime/lua/paw/views/qflist.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callback: paw.canvas.open_view | teal |
| [runtime/lua/paw/views/qflist.lua](../../../../../../runtime/lua/paw/views/qflist.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [runtime/lua/paw/views/qflist.lua](../../../../../../runtime/lua/paw/views/qflist.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [runtime/lua/paw/views/qflist.lua](../../../../../../runtime/lua/paw/views/qflist.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.buf_create, paw.layout.buf_of, paw.layout.buftype, paw.layout.close, paw.layout.current, paw.layout.enter, paw.layout.get, paw.layout.leaf | teal |
| [runtime/lua/paw/views/qflist.lua](../../../../../../runtime/lua/paw/views/qflist.lua) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callback: paw.mouse.wheel | teal |
| [runtime/lua/paw/views/qflist.lua](../../../../../../runtime/lua/paw/views/qflist.lua) | [runtime/lua/paw/qf.tl](../../../../../../runtime/lua/paw/qf.tl) | Invokes supplied callbacks: paw.qf.count, paw.qf.current, paw.qf.fix, paw.qf.fix_title, paw.qf.jump, paw.qf.loc_stack, paw.qf.stack, paw.qf.where | teal |
| [runtime/lua/paw/views/qflist.lua](../../../../../../runtime/lua/paw/views/qflist.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.focused, paw.ui.keybar, paw.ui.notify, paw.ui.titlebar, paw.ui.views | teal |
| [runtime/lua/paw/views/qflist.lua](../../../../../../runtime/lua/paw/views/qflist.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit, paw.util.merge | teal |
