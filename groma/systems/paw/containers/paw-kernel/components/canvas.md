---
type: C4 Component
title: Canvas
status: stable
groma:
  id: canvas
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/canvas.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.canvas_image, paw.api.grid_image, paw.api.smufl_outline, paw.api.str_width, paw.api.ui_attached, paw.api.ui_redraw, paw.api.ui_redraws, paw.api.ui_view_snapshot | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callbacks: paw.api.log, paw.api.now | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, require("paw.events") | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.feed, paw.keymap.mode, paw.keymap.set_mode | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callback: paw.limit.named | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callback: paw.mouse.to_view | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [runtime/lua/paw/panes.tl](../../../../../../runtime/lua/paw/panes.tl) | Invokes supplied callbacks: paw.panes.cells, paw.panes.stays | teal |
| [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui, paw.ui.drawing, paw.ui.drawing_win, paw.ui.float, paw.ui.focused, paw.ui.views | teal |
