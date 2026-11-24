---
type: C4 Component
title: Mouse
status: stable
groma:
  id: mouse
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/mouse.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callback: paw.canvas.view_pointer | teal |
| [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callbacks: paw.limit.named, require("paw.limit") | teal |
| [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.rects, paw.ui.views | teal |
