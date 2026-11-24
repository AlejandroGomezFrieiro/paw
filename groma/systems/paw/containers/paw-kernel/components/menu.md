---
type: C4 Component
title: Menu
status: stable
groma:
  id: menu
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/menu.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/menu.tl](../../../../../../runtime/lua/paw/menu.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/menu.tl](../../../../../../runtime/lua/paw/menu.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/menu.tl](../../../../../../runtime/lua/paw/menu.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, require("paw.draw") | teal |
| [runtime/lua/paw/menu.tl](../../../../../../runtime/lua/paw/menu.tl) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.overlays, paw.mouse.wheel, require("paw.mouse") | teal |
| [runtime/lua/paw/menu.tl](../../../../../../runtime/lua/paw/menu.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/menu.tl](../../../../../../runtime/lua/paw/menu.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit, require("paw.util") | teal |
