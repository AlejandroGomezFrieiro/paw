---
type: C4 Component
title: Panes
status: stable
groma:
  id: panes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/panes.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas.cell, paw.canvas.cell_event, paw.canvas.open_views, paw.canvas.titles, paw.canvas.view_pointer | teal |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.set_mode | teal |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.bind, paw.layout.buf_of, paw.layout.close, paw.layout.current, paw.layout.drag_border, paw.layout.enter, paw.layout.find, paw.layout.find_id, paw.layout.settle, paw.layout.tab_close, paw.layout.tab_go, paw.layout.tab_move, paw.layout.tab_new, paw.layout.tab_title, paw.layout.title, require("paw.layout") | teal |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callbacks: paw.limit.named, require("paw.limit") | teal |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callback: paw.mouse.to_view | teal |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | Invokes supplied callback: paw.statusline.tabline_always | teal |
| [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.bars, paw.ui.float, paw.ui.focused, paw.ui.layout, paw.ui.notify, paw.ui.place, paw.ui.show, paw.ui.start_layout, paw.ui.tab, paw.ui.tabs, paw.ui.views | teal |
