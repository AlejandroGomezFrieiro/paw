---
type: C4 Component
title: Keybar
status: stable
groma:
  id: paw-keybar
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/keybar.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/keybar.tl](../../../../../../runtime/lua/paw/keybar.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/keybar.tl](../../../../../../runtime/lua/paw/keybar.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/keybar.tl](../../../../../../runtime/lua/paw/keybar.tl) | [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | Invokes supplied callbacks: paw.insert, paw.insert.count, paw.insert.list | teal |
| [runtime/lua/paw/keybar.tl](../../../../../../runtime/lua/paw/keybar.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.expand, paw.keymap.human, paw.keymap.list | teal |
| [runtime/lua/paw/keybar.tl](../../../../../../runtime/lua/paw/keybar.tl) | [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | Invokes supplied callbacks: paw.roll_draw, paw.roll_draw.describe, paw.roll_draw.edge_now, paw.roll_draw.list, paw.roll_draw.stepping | teal |
| [runtime/lua/paw/keybar.tl](../../../../../../runtime/lua/paw/keybar.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.views | teal |
